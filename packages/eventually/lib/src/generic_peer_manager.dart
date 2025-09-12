import 'dart:async';
import 'dart:typed_data';

import 'cid.dart';
import 'peer.dart';
import 'transport.dart';
import 'peer_config.dart';
import 'protocol.dart';
import 'block.dart';

/// Generic peer manager that doesn't own the transport layer.
///
/// This peer manager handles peer relationships and connections but delegates
/// network operations to a transport that is owned by the synchronizer.
/// The synchronizer orchestrates communication between this peer manager
/// and the transport layer.
class GenericPeerManager implements PeerManager {
  /// Configuration for this peer manager.
  final PeerConfig config;

  /// Default protocol for sync operations.
  final SyncProtocol syncProtocol;

  // Internal state
  final Map<PeerId, Peer> _peers = {};
  @Deprecated('use _peers instead')
  final Map<PeerId, GenericPeerConnection> _connections = {};
  final Map<TransportDeviceAddress, PeerId> _transportToPeerIdMap = {};

  final StreamController<PeerEvent> _peerEventsController =
      StreamController<PeerEvent>.broadcast();
  final StreamController<OutgoingBytes> _outgoingBytesController =
      StreamController<OutgoingBytes>.broadcast();

  bool _isDisposed = false;

  /// Creates a new generic peer manager.
  GenericPeerManager({required this.config, SyncProtocol? syncProtocol})
    : syncProtocol = syncProtocol ?? BitSwapProtocol();

  @override
  Iterable<Peer> get connectedPeers => _peers.values.where((p) => p.isActive);

  @override
  Iterable<Peer> get peers => _peers.values;

  @override
  Stream<OutgoingBytes> get outgoingBytes => _outgoingBytesController.stream;

  @override
  Stream<PeerEvent> get peerEvents => _peerEventsController.stream;

  @override
  Future<void> handleIncomingBytes(IncomingBytes incomingBytes) async {
    try {
      final peerId = _transportToPeerIdMap[incomingBytes.device.address];
      if (peerId != null) {
        final peer = _peers[peerId];
        if (peer != null) {
          final message = syncProtocol.decodeMessage(incomingBytes.bytes);
          // TODO: parse the message and handle it accordingly
          throw UnimplementedError("handleIncomingBytes is not implemented");
        }
        // Ignore unknown peers
      }
    } catch (e) {
      debugPrint(
        'Failed to decode message from ${incomingBytes.device.address}: $e',
      );
    }
  }

  @override
  Future<Peer> registerDeviceAsPeer(
    TransportDevice device, {
    Duration? timeout = const Duration(seconds: 10),
  }) async {
    if (_isDisposed) throw Exception("PeerManager is disposed");

    // check if a peer already exists.
    final peerId = _transportToPeerIdMap[device.address];
    if (peerId != null && _peers.containsKey(peerId)) {
      return _peers[peerId]!;
    }

    throw UnimplementedError("perform handshake");
    // TODO: use a completer and perform the handshake.
  }

  @override
  Future<void> connectToPeer(PeerId peerId) async {
    if (_isDisposed) {
      throw PeerException('Peer manager is disposed');
    }

    Peer? peer = _peers[peerId.value];
    if (peer == null) {
      throw PeerException('Unknown peer: $peerId');
    }

    _peers[peerId] = peer.copyWith(isActive: true);
  }

  @override
  PeerConnection? getConnection(PeerId peerId) {
    return _connections[peerId];
  }

  @override
  Future<void> disconnect(PeerId peerId) async {
    if (_isDisposed) return;

    final connection = _connections[peerId];
    final peer = _peers[peerId];

    if (connection != null) {
      await connection.close();
      _connections.remove(peerId);
    }

    if (peer?.transportPeer != null) {
      _transportToPeerIdMap.remove(peer!.transportPeer.address);
    }

    _peers.remove(peerId);

    if (peer != null) {
      _peerEventsController.add(
        PeerDisconnected(peer: peer, timestamp: DateTime.now()),
      );
    }
  }

  @override
  Future<void> disconnectAll() async {
    if (_isDisposed) return;

    final peerIds = _peers.keys.toList();

    for (final peerId in peerIds) {
      await disconnect(peerId);
    }
  }

  @override
  Future<List<Peer>> findPeersWithBlock(CID cid) async {
    if (_isDisposed) return [];

    final peersWithBlock = <Peer>[];

    for (final peer in connectedPeers) {
      final connection = _connections[peer.id];
      if (connection != null && await connection.hasBlock(cid)) {
        peersWithBlock.add(peer);
      }
    }

    return peersWithBlock;
  }

  @override
  Future<void> broadcast(Message message) async {
    if (_isDisposed) return;

    final broadcastFutures = <Future>[];

    for (final connection in _connections.values) {
      if (connection.isConnected) {
        broadcastFutures.add(
          connection
              .sendMessage(message)
              .catchError(
                (e) => debugPrint(
                  'Failed to broadcast to ${connection.peer?.id}: $e',
                ),
              ),
        );
      }
    }

    await Future.wait(broadcastFutures);
  }

  @override
  Future<PeerStats> getStats() async {
    if (_isDisposed) {
      return PeerStats(
        totalPeers: 0,
        connectedPeers: 0,
        totalMessages: 0,
        totalBytesReceived: 0,
        totalBytesSent: 0,
      );
    }

    return PeerStats(
      totalPeers: _peers.length,
      connectedPeers: connectedPeers.length,
      totalMessages: 0,
      totalBytesReceived: 0,
      totalBytesSent: 0,
    );
  }

  /// Disposes of the peer manager and releases resources.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    await disconnectAll();
    await _peerEventsController.close();
    _transportToPeerIdMap.clear();
  }
}

/// Generic peer connection that uses a transport for network operations.
class GenericPeerConnection implements PeerConnection {
  /// The peer this connection is for.
  final Peer _peer;

  /// The transport layer for network communication.
  final Transport transport;

  /// The protocol for sync operations.
  final SyncProtocol syncProtocol;

  bool _isConnected = false;
  bool _isDisposed = false;
  final StreamController<Message> _messagesController =
      StreamController<Message>.broadcast();

  /// Creates a new generic peer connection.
  GenericPeerConnection({
    required Peer peer,
    required this.transport,
    required this.syncProtocol,
  }) : _peer = peer;

  @override
  Peer? get peer => _peer;

  @override
  bool get isConnected => _isConnected && !_isDisposed;

  @override
  Stream<Message> get messages => _messagesController.stream;

  /// Initializes the connection.
  Future<void> initialize() async {
    if (_isDisposed) {
      throw PeerException('Connection is disposed');
    }

    _isConnected = true;
  }

  /// Handles incoming bytes from the transport.
  void handleIncomingBytes(Uint8List bytes) {
    if (_isDisposed || !_isConnected) return;

    // Decode the message using the sync protocol
    try {
      final message = syncProtocol.decodeMessage(bytes) as Message;
      _handleMessage(message);
    } catch (e) {
      debugPrint('Failed to decode message from ${_peer.id}: $e');
    }
  }

  void _handleMessage(Message message) {
    // Handle different message types
    // This would typically update internal state and notify listeners
    debugPrint('Received message from ${_peer.id}: ${message.runtimeType}');
    _messagesController.add(message);
  }

  @override
  Future<void> connect() async {
    if (_isDisposed) {
      throw PeerException('Connection is disposed');
    }
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    if (_isDisposed) return;
    _isConnected = false;
    _isDisposed = true;
    await _messagesController.close();
  }

  @override
  Future<void> sendMessage(dynamic message) async {
    if (_isDisposed || !_isConnected) {
      throw PeerException('Connection not available');
    }

    try {
      final bytes = syncProtocol.encodeMessage(message);
      await transport.sendBytes(_peer.transportPeer!, bytes);
    } catch (e) {
      throw PeerException('Failed to send message to ${_peer.id}', cause: e);
    }
  }

  @override
  Future<Block?> requestBlock(CID cid) async {
    if (!isConnected) return null;

    try {
      final request = Want(cids: {cid});
      await sendMessage(request);

      // This is a simplified implementation
      // In practice, you'd wait for the response and handle timeouts
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<Block>> requestBlocks(List<CID> cids) async {
    if (!isConnected) return [];

    try {
      final request = Want(cids: cids.toSet());
      await sendMessage(request);

      // This is a simplified implementation
      // In practice, you'd wait for the response and handle timeouts
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> sendBlock(Block block) async {
    if (!isConnected) return;

    try {
      final message = Have(cids: {block.cid});
      await sendMessage(message);
    } catch (e) {
      // Ignore send errors for now
    }
  }

  @override
  Future<bool> hasBlock(CID cid) async {
    if (!isConnected) return false;

    try {
      // This would typically send a query message and wait for response
      // Simplified implementation
      return false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Set<String>> getCapabilities() async {
    if (!isConnected) return {};

    // This would typically exchange capability information during handshake
    // Simplified implementation
    return {'bitswap'};
  }

  @override
  Future<Duration> ping() async {
    if (!isConnected) throw PeerException('Not connected');

    try {
      // This would typically send a ping message and wait for pong
      // Simplified implementation - just return a mock latency
      return Duration(milliseconds: 50);
    } catch (e) {
      throw PeerException('Ping failed', cause: e);
    }
  }

  Future<void> close() async {
    if (_isDisposed) return;

    _isConnected = false;
    _isDisposed = true;
    await _messagesController.close();
  }
}

/// Debug print function for development.
void debugPrint(String message) {
  print('[GenericPeerManager] $message');
}
