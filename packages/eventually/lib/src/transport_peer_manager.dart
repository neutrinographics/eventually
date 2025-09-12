import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:eventually/src/block.dart';
import 'cid.dart';
import 'peer.dart';
import 'peer_config.dart';
import 'protocol.dart';
import 'transport.dart';

/// Peer manager implementation using the Transport interface.
///
/// This class manages the lifecycle of peer connections, including discovery,
/// handshake, protocol negotiation, and message routing between the transport
/// layer and application layer.
/// TODO: Is this a duplicate of transport?
class TransportPeerManager implements PeerManager {
  /// The transport layer for network communication.
  final Transport transport;

  /// Configuration for this peer manager.
  final PeerConfig config;

  /// Default protocol for sync operations.
  final SyncProtocol syncProtocol;

  // Internal state
  final Map<PeerId, Peer> _peers = {};
  final Map<PeerId, TransportPeerConnection> _connections = {};
  final Map<String, TransportPeer> _discoveredTransportPeers = {};
  final Map<String, PeerId?> _transportToPeerIdMap = {};
  final Map<PeerId, String> _peerIdToTransportMap = {};

  final StreamController<PeerEvent> _peerEventsController =
      StreamController<PeerEvent>.broadcast();

  StreamSubscription<IncomingBytes>? _incomingBytesSubscription;
  Timer? _discoveryTimer;
  Timer? _healthCheckTimer;
  bool _isInitialized = false;
  bool _isDiscoveryActive = false;

  /// Creates a new transport-based peer manager.
  TransportPeerManager({
    required this.transport,
    required this.config,
    SyncProtocol? syncProtocol,
  }) : syncProtocol = syncProtocol ?? BitSwapProtocol();

  /// Initializes the peer manager.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await transport.initialize();

    // Set up incoming bytes handling
    _incomingBytesSubscription = transport.incomingBytes.listen(
      _handleIncomingBytes,
      onError: (error) => _handleTransportError(error),
    );

    _schedulePeriodicDiscovery();
    if (config.enableHealthCheck) {
      _scheduleHealthCheck();
    }

    _isInitialized = true;
  }

  /// Shuts down the peer manager.
  Future<void> dispose() async {
    if (!_isInitialized) return;

    _isDiscoveryActive = false;
    _discoveryTimer?.cancel();
    _healthCheckTimer?.cancel();

    await disconnectAll();
    await _incomingBytesSubscription?.cancel();
    await transport.shutdown();
    await _peerEventsController.close();

    _isInitialized = false;
  }

  @override
  Iterable<Peer> get connectedPeers =>
      _peers.values.where((peer) => peer.isActive);

  @override
  Stream<PeerEvent> get peerEvents => _peerEventsController.stream;

  @override
  Future<void> startDiscovery() async {
    if (_isDiscoveryActive || !_isInitialized) return;

    _isDiscoveryActive = true;
    debugPrint('🔍 Starting peer discovery (${config.nodeId})');

    try {
      await _performDiscovery();
      // TODO: do we really ned this event?
      // _emitPeerEvent(PeerDiscoveryStarted(timestamp: DateTime.now()));
    } catch (e) {
      debugPrint('❌ Failed to start discovery: $e');
      _isDiscoveryActive = false;
      rethrow;
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isDiscoveryActive) return;

    _isDiscoveryActive = false;
    debugPrint('🛑 Stopping peer discovery');

    // TODO: do we really need this event?
    // _emitPeerEvent(PeerDiscoveryStopped(timestamp: DateTime.now()));
  }

  @override
  Future<PeerConnection> connectToEndpoint(TransportPeerAddress address) async {
    if (!_isInitialized) {
      throw PeerException('Peer manager not initialized');
    }

    // Check if we already have a connection to this endpoint
    final existingPeerId = _transportToPeerIdMap[address.value];
    if (existingPeerId != null) {
      final existingConnection = _connections[existingPeerId];
      if (existingConnection != null && existingConnection.isConnected) {
        return existingConnection;
      }
    }

    // Find the transport peer for this endpoint
    final transportPeer = _discoveredTransportPeers[address.value];
    if (transportPeer == null) {
      throw PeerException('Unknown transport endpoint: $address');
    }

    return await _connectToTransportPeer(transportPeer);
  }

  @override
  PeerConnection? getConnection(PeerId peerId) {
    return _connections[peerId];
  }

  @override
  Future<void> disconnect(PeerId peerId) async {
    final connection = _connections[peerId];
    if (connection != null) {
      await connection.disconnect();
      _connections.remove(peerId);

      final peer = _peers[peerId];
      if (peer != null) {
        _peers[peerId] = peer.copyWith(isActive: false);
        _emitPeerEvent(
          PeerDisconnected(
            peer: peer,
            timestamp: DateTime.now(),
            reason: 'Manual disconnect',
          ),
        );
      }
    }
  }

  @override
  Future<void> disconnectAll() async {
    final disconnectFutures = _connections.keys
        .map((peerId) => disconnect(peerId))
        .toList();
    await Future.wait(disconnectFutures);
  }

  @override
  Future<List<Peer>> findPeersWithBlock(CID cid) async {
    // This would typically involve querying connected peers
    // For now, return all connected peers as potential sources
    return connectedPeers.toList();
  }

  @override
  Future<void> broadcast(Message message) async {
    final messageBytes = message.toBytes();
    final broadcastFutures = <Future>[];

    for (final peer in connectedPeers) {
      final transportAddress = _peerIdToTransportMap[peer.id];
      if (transportAddress != null) {
        final transportPeer = _discoveredTransportPeers[transportAddress];
        if (transportPeer != null) {
          broadcastFutures.add(
            transport
                .sendBytes(transportPeer, messageBytes)
                .catchError(
                  (e) => debugPrint('Failed to broadcast to ${peer.id}: $e'),
                ),
          );
        }
      }
    }

    await Future.wait(broadcastFutures);
  }

  @override
  Future<PeerStats> getStats() async {
    return PeerStats(
      totalPeers: _peers.length,
      connectedPeers: connectedPeers.length,
      totalMessages: 0, // Would track this in real implementation
      totalBytesReceived: 0, // Would track this in real implementation
      totalBytesSent: 0, // Would track this in real implementation
    );
  }

  // Private methods

  Future<void> _performDiscovery() async {
    try {
      final discoveredPeers = await transport.discoverPeers(
        timeout: const Duration(seconds: 10),
      );

      for (final transportPeer in discoveredPeers) {
        _discoveredTransportPeers[transportPeer.address.value] = transportPeer;

        if (shouldAutoConnect(transportPeer)) {
          _autoConnectToTransportPeer(transportPeer);
        }
      }
    } catch (e) {
      debugPrint('Discovery failed: $e');
    }
  }

  bool shouldAutoConnect(TransportPeer transportPeer) {
    if (!config.autoConnect) return false;

    // Don't auto-connect if we're already connected to this transport peer
    final existingPeerId = _transportToPeerIdMap[transportPeer.address.value];
    if (existingPeerId != null) {
      final peer = _peers[existingPeerId];
      if (peer?.isActive == true) return false;
    }

    return true;
  }

  void _autoConnectToTransportPeer(TransportPeer transportPeer) {
    // Use a small random delay to avoid connection storms
    final delay = Duration(milliseconds: Random().nextInt(1000));
    Timer(delay, () async {
      try {
        await _connectToTransportPeer(transportPeer);
      } catch (e) {
        debugPrint('Auto-connect failed for ${transportPeer.address}: $e');
      }
    });
  }

  Future<TransportPeerConnection> _connectToTransportPeer(
    TransportPeer transportPeer,
  ) async {
    try {
      // Perform handshake to discover peer identity
      // For now, skip handshake and create a temporary connection
      // In a full implementation, you'd perform the handshake protocol

      // Wait for handshake response (simplified - in practice you'd have a timeout)
      // For now, create a connection without waiting for the full handshake
      final tempPeerId = PeerId('temp_${transportPeer.address.value}');
      final connection = TransportPeerConnection(
        transportPeer: transportPeer,
        transport: transport,
        syncProtocol: syncProtocol,
      );

      _connections[tempPeerId] = connection;
      _transportToPeerIdMap[transportPeer.address.value] = tempPeerId;
      _peerIdToTransportMap[tempPeerId] = transportPeer.address.value;

      final peer = Peer(
        id: tempPeerId,
        transportPeer: transportPeer,
        metadata: {'handshake_pending': true},
      );

      _peers[tempPeerId] = peer;

      _emitPeerEvent(PeerConnected(peer: peer, timestamp: DateTime.now()));

      return connection;
    } catch (e) {
      throw PeerException('Failed to connect to transport peer', cause: e);
    }
  }

  void _handleIncomingBytes(IncomingBytes incomingBytes) {
    final transportAddress = incomingBytes.peer.address.value;
    var peerId = _transportToPeerIdMap[transportAddress];

    // If we don't know this peer yet, handle as potential new connection
    if (peerId == null) {
      _handleNewPeerBytes(incomingBytes);
      return;
    }

    final connection = _connections[peerId];
    if (connection != null) {
      connection._handleIncomingBytes(incomingBytes.bytes);
    }
  }

  void _handleNewPeerBytes(IncomingBytes incomingBytes) {
    // This would typically handle handshake messages from new peers
    // For now, create a temporary peer connection
    final transportPeer = incomingBytes.peer;
    final tempPeerId = PeerId('temp_${transportPeer.address.value}');

    if (!_transportToPeerIdMap.containsKey(transportPeer.address.value)) {
      _transportToPeerIdMap[transportPeer.address.value] = tempPeerId;
      _peerIdToTransportMap[tempPeerId] = transportPeer.address.value;
      _discoveredTransportPeers[transportPeer.address.value] = transportPeer;

      final connection = TransportPeerConnection(
        transportPeer: transportPeer,
        transport: transport,
        syncProtocol: syncProtocol,
      );
      _connections[tempPeerId] = connection;

      final peer = Peer(id: tempPeerId, transportPeer: transportPeer);
      _peers[tempPeerId] = peer;

      _emitPeerEvent(PeerConnected(peer: peer, timestamp: DateTime.now()));
    }

    final connection = _connections[tempPeerId];
    connection?._handleIncomingBytes(incomingBytes.bytes);
  }

  void _handleTransportError(dynamic error) {
    debugPrint('Transport error: $error');
  }

  void _schedulePeriodicDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(config.discoveryInterval, (_) async {
      if (_isDiscoveryActive) {
        await _performDiscovery();
      }
    });
  }

  void _scheduleHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(config.healthCheckInterval, (_) async {
      await _performHealthCheck();
    });
  }

  Future<void> _performHealthCheck() async {
    final peersToCheck = connectedPeers.toList();
    for (final peer in peersToCheck) {
      final transportAddress = _peerIdToTransportMap[peer.id];
      if (transportAddress != null) {
        final transportPeer = _discoveredTransportPeers[transportAddress];
        if (transportPeer != null) {
          final isReachable = await transport.isPeerReachable(transportPeer);
          if (!isReachable) {
            await disconnect(peer.id);
          }
        }
      }
    }
  }

  void _emitPeerEvent(PeerEvent event) {
    if (!_peerEventsController.isClosed) {
      _peerEventsController.add(event);
    }
  }
}

/// Peer connection implementation.
class TransportPeerConnection implements PeerConnection {
  final TransportPeer transportPeer;
  final Transport transport;
  final SyncProtocol syncProtocol;

  final StreamController<Message> _messagesController =
      StreamController<Message>.broadcast();

  bool _isConnected = true;
  Peer? _peer;

  TransportPeerConnection({
    required this.transportPeer,
    required this.transport,
    required this.syncProtocol,
  });

  @override
  Peer? get peer => _peer;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<Message> get messages => _messagesController.stream;

  @override
  Future<void> connect() async {
    // Connection is established when the object is created
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    await _messagesController.close();
  }

  @override
  Future<void> sendMessage(message) async {
    if (!_isConnected) {
      throw ConnectionException('Connection is not active');
    }

    Uint8List bytes;
    if (message is Message) {
      bytes = message.toBytes();
    } else {
      throw ArgumentError('Message must be of type Message');
    }

    await transport.sendBytes(transportPeer, bytes);
  }

  @override
  Future<Block?> requestBlock(CID cid) async {
    final request = BlockRequest(cid: cid);
    await sendMessage(request);

    // In a real implementation, you'd wait for the response
    // This is simplified for the migration
    return null;
  }

  @override
  Future<List<Block>> requestBlocks(List<CID> cids) async {
    final futures = cids.map((cid) => requestBlock(cid));
    final results = await Future.wait(futures);
    return results.whereType<Block>().toList();
  }

  @override
  Future<void> sendBlock(dynamic block) async {
    // Simplified - in practice you'd create proper block response
    final response = Ping(); // Placeholder
    await sendMessage(response);
  }

  @override
  Future<bool> hasBlock(CID cid) async {
    // This would typically send a query message
    // Simplified for migration
    return false;
  }

  @override
  Future<Set<String>> getCapabilities() async {
    return syncProtocol.capabilities;
  }

  @override
  Future<Duration> ping() async {
    final start = DateTime.now();
    final pingMessage = Ping();
    await sendMessage(pingMessage);

    // In practice, you'd wait for the pong response
    // This is simplified for the migration
    return DateTime.now().difference(start);
  }

  void _handleIncomingBytes(Uint8List bytes) {
    try {
      // Decode the message using the protocol
      // For now, create a simple ping message
      // In practice, you'd decode the actual protocol message
      final message = Ping();
      if (!_messagesController.isClosed) {
        _messagesController.add(message);
      }
    } catch (e) {
      debugPrint('Failed to decode incoming message: $e');
    }
  }
}

/// Event classes for the new peer manager.
class PeerDiscoveryStarted {
  const PeerDiscoveryStarted({required this.timestamp});
  final DateTime timestamp;
}

class PeerDiscoveryStopped {
  const PeerDiscoveryStopped({required this.timestamp});
  final DateTime timestamp;
}

/// Debug print function.
void debugPrint(String message) {
  print('[TransportPeerManager] $message');
}
