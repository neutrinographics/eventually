import 'dart:async';
import 'dart:math';
import 'package:eventually/src/transport.dart';
import 'package:meta/meta.dart';
import 'cid.dart';
import 'peer.dart';
import 'peer_config.dart';
import 'peer_handshake.dart';
import 'transport_endpoint.dart';

/// Base class that handles common transport-to-peer connection logic.
///
/// This class implements the complex boilerplate of managing peer connections,
/// discovery, handshake, and connection lifecycle. Subclasses only need to
/// provide a transport manager and can optionally customize behavior through
/// override methods.
abstract class TransportPeerManager implements PeerManager {
  /// Configuration for this peer manager.
  final PeerConfig config;

  /// Handshake handler for peer identity discovery.
  final PeerHandshake handshake;

  // Internal state
  final Map<String, Peer> _peers = {};
  final Map<String, PeerConnection> _connections = {};
  final Map<String, TransportPeer> _discoveredTransportPeers = {};
  final Map<String, int> _connectionAttempts = {};
  final Map<String, DateTime> _lastConnectionAttempt = {};
  final Random _random = Random();

  final StreamController<PeerEvent> _peerEventsController =
      StreamController<PeerEvent>.broadcast();

  StreamSubscription? _transportEventsSubscription;
  Timer? _discoveryTimer;
  Timer? _healthCheckTimer;
  bool _isDiscoveryActive = false;
  bool _isDisposed = false;

  /// Creates a new transport-based peer manager.
  TransportPeerManager({required this.config, PeerHandshake? handshake})
    : handshake = handshake ?? const DefaultPeerHandshake() {
    _initializeTransportEventHandling();
    _schedulePeriodicDiscovery();
    if (config.enableHealthCheck) {
      _scheduleHealthCheck();
    }
  }

  /// Abstract method - subclasses provide their transport manager.
  TransportManager get transport;

  @override
  Iterable<Peer> get connectedPeers => _peers.values.where(
    (peer) => peer.isActive && _connections[peer.id]?.isConnected == true,
  );

  @override
  Stream<PeerEvent> get peerEvents => _peerEventsController.stream;

  @override
  Future<void> startDiscovery() async {
    if (_isDiscoveryActive || _isDisposed) return;

    _isDiscoveryActive = true;
    debugPrint('🔍 Starting peer discovery (${config.nodeId})');

    try {
      await transport.startDiscovery();
      // Discovery started - could emit custom event if needed
      debugPrint('✅ Peer discovery started');
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

    await transport.stopDiscovery();
    // Discovery stopped - could emit custom event if needed
    debugPrint('✅ Peer discovery stopped');
  }

  @override
  Future<PeerConnection> connectToEndpoint(String endpointAddress) async {
    if (_isDisposed) {
      throw PeerException('Peer manager is disposed');
    }

    // Check if we already have a peer connection for this endpoint
    final existingPeer = _peers.values.cast<Peer?>().firstWhere(
      (peer) => peer?.transportPeer.address.value == endpointAddress,
      orElse: () => null,
    );

    if (existingPeer != null) {
      final existingConnection = _connections[existingPeer.id];
      if (existingConnection?.isConnected == true) {
        return existingConnection!;
      }
    }

    // Find the transport peer
    final transportPeer = _discoveredTransportPeers.values
        .cast<TransportPeer?>()
        .firstWhere(
          (peer) => peer?.address.value == endpointAddress,
          orElse: () => null,
        );

    if (transportPeer == null) {
      throw PeerException('Transport peer not found: $endpointAddress');
    }

    return await _connectToTransportPeer(transportPeer);
  }

  @override
  PeerConnection? getConnection(String peerId) {
    return _connections[peerId];
  }

  @override
  Future<void> disconnect(String peerId) async {
    final peer = _peers[peerId];
    final connection = _connections[peerId];

    if (connection != null) {
      await connection.disconnect();
      _connections.remove(peerId);
    }

    if (peer != null) {
      _peers.remove(peerId);
      _emitPeerEvent(
        PeerDisconnected(
          peer: peer,
          timestamp: DateTime.now(),
          reason: 'Manual disconnect',
        ),
      );
      debugPrint('👋 Disconnected from peer: $peerId');
    }
  }

  @override
  Future<void> disconnectAll() async {
    final peerIds = List.of(_peers.keys);
    for (final peerId in peerIds) {
      await disconnect(peerId);
    }
    await transport.disconnectAll();
  }

  @override
  Future<List<Peer>> findPeersWithBlock(CID cid) async {
    final peersWithBlock = <Peer>[];

    for (final connection in _connections.values) {
      if (connection.isConnected && connection.peer != null) {
        try {
          final hasBlock = await connection.hasBlock(cid);
          if (hasBlock) {
            peersWithBlock.add(connection.peer!);
          }
        } catch (e) {
          debugPrint(
            '⚠️ Peer ${connection.peer?.id} didn\'t respond to hasBlock query: $e',
          );
        }
      }
    }

    return peersWithBlock;
  }

  @override
  Future<void> broadcast(Message message) async {
    final activeConnections = _connections.values
        .where((c) => c.isConnected)
        .toList();

    final futures = activeConnections.map((connection) async {
      try {
        await connection.sendMessage(message);
      } catch (e) {
        debugPrint('⚠️ Failed to broadcast to peer ${connection.peer?.id}: $e');
      }
    });

    await Future.wait(futures);
  }

  @override
  Future<PeerStats> getStats() async {
    final connectedCount = connectedPeers.length;
    final transportStats = await transport.getStats();

    return PeerStats(
      totalPeers: _peers.length,
      connectedPeers: connectedCount,
      totalMessages: 0, // Would track in a real implementation
      totalBytesReceived: transportStats.totalBytesReceived,
      totalBytesSent: transportStats.totalBytesSent,
      details: {
        'transport_endpoints': transportStats.totalEndpoints,
        'connected_endpoints': transportStats.connectedEndpoints,
        'discovered_transport_peers': _discoveredTransportPeers.length,
        'failed_connection_attempts': _connectionAttempts.length,
        'config': config.toString(),
      },
    );
  }

  /// Override point: Determines if auto-connection should be attempted.
  @protected
  bool shouldAutoConnect(TransportPeer transportPeer) {
    if (!config.autoConnect) return false;
    if (_connections.length >= config.maxConnections) return false;
    if (_isConnectionInProgress(transportPeer.address.value)) return false;
    if (_hasRecentFailedAttempt(transportPeer.address.value)) return false;

    return true;
  }

  /// Override point: Called when a transport peer is discovered.
  @protected
  Future<void> onTransportPeerDiscovered(TransportPeer transportPeer) async {
    if (shouldAutoConnect(transportPeer)) {
      await _autoConnectToTransportPeer(transportPeer);
    }
  }

  /// Override point: Called when a transport peer is lost.
  @protected
  Future<void> onTransportPeerLost(TransportPeer transportPeer) async {
    // Find and disconnect any peers using this transport
    final affectedPeers = _peers.values
        .where((peer) => peer.transportPeer.address == transportPeer.address)
        .toList();

    for (final peer in affectedPeers) {
      await disconnect(peer.id);
    }
  }

  /// Override point: Called when a transport connection is established.
  @protected
  Future<void> onTransportConnected(TransportEndpoint endpoint) async {
    // Transport connection established - handshake will complete the peer connection
    debugPrint('🔗 Transport connected: ${endpoint.address}');
  }

  /// Override point: Called when a transport connection is lost.
  @protected
  Future<void> onTransportDisconnected(
    TransportEndpoint endpoint,
    String? reason,
  ) async {
    // Find peers using this transport endpoint and mark them as disconnected
    final affectedPeers = _peers.values
        .where((peer) => peer.transportPeer.address.value == endpoint.address)
        .toList();

    for (final peer in affectedPeers) {
      final connection = _connections[peer.id];
      if (connection != null) {
        _connections.remove(peer.id);
        _peers[peer.id] = peer.updateActivity(false);

        _emitPeerEvent(
          PeerDisconnected(
            peer: peer,
            timestamp: DateTime.now(),
            reason: reason ?? 'Transport disconnected',
          ),
        );

        // Schedule reconnection if enabled
        if (config.enableAutoReconnect && _shouldAttemptReconnection(peer.id)) {
          _scheduleReconnection(peer);
        }
      }
    }
  }

  /// Override point: Selects which transport peer to connect to from available options.
  @protected
  TransportPeer? selectTransportPeer(List<TransportPeer> availablePeers) {
    if (availablePeers.isEmpty) return null;

    switch (config.selectionStrategy) {
      case PeerSelectionStrategy.firstAvailable:
        return availablePeers.first;

      case PeerSelectionStrategy.random:
        return availablePeers[_random.nextInt(availablePeers.length)];

      case PeerSelectionStrategy.leastConnections:
        // For simplicity, just return random - real implementation would track connection counts
        return availablePeers[_random.nextInt(availablePeers.length)];

      case PeerSelectionStrategy.mostReliable:
        // For simplicity, just return first - real implementation would track reliability
        return availablePeers.first;

      case PeerSelectionStrategy.lowestLatency:
        // For simplicity, just return first - real implementation would measure latency
        return availablePeers.first;

      case PeerSelectionStrategy.roundRobin:
        // For simplicity, just return random - real implementation would maintain round-robin state
        return availablePeers[_random.nextInt(availablePeers.length)];
    }
  }

  /// Initializes transport event handling.
  void _initializeTransportEventHandling() {
    _transportEventsSubscription = transport.transportEvents.listen(
      (event) => _handleTransportEvent(event),
      onError: (error) {
        debugPrint('❌ Transport event error: $error');
      },
    );
  }

  /// Handles transport events.
  Future<void> _handleTransportEvent(TransportEvent event) async {
    if (_isDisposed) return;

    try {
      switch (event) {
        case EndpointDiscovered():
          await _handleEndpointDiscovered(event);
          break;

        case TransportConnected():
          await onTransportConnected(event.endpoint);
          break;

        case TransportDisconnected():
          await onTransportDisconnected(event.endpoint, event.reason);
          break;

        case TransportDataReceived():
          // Data is handled by individual connections
          break;
      }
    } catch (e) {
      debugPrint('❌ Error handling transport event: $e');
    }
  }

  /// Handles endpoint discovered events.
  Future<void> _handleEndpointDiscovered(EndpointDiscovered event) async {
    final endpoint = event.endpoint;

    // Convert TransportEndpoint to TransportPeer
    final transportPeer = TransportPeer(
      address: TransportPeerAddress(endpoint.address),
      displayName:
          endpoint.metadata['endpoint_name']?.toString() ?? endpoint.address,
      protocol: endpoint.protocol,
      metadata: endpoint.metadata,
    );

    debugPrint(
      '🔍 Discovered transport peer: ${transportPeer.displayName} (${transportPeer.address})',
    );

    // Store discovered transport peer
    _discoveredTransportPeers[transportPeer.address.value] = transportPeer;

    // Notify subclass
    await onTransportPeerDiscovered(transportPeer);
  }

  /// Attempts to auto-connect to a transport peer.
  Future<void> _autoConnectToTransportPeer(TransportPeer transportPeer) async {
    if (_isDisposed) return;

    debugPrint(
      '🚀 Auto-connecting to transport peer: ${transportPeer.displayName}',
    );

    try {
      await _connectToTransportPeer(transportPeer);
    } catch (e) {
      debugPrint('❌ Auto-connection failed to ${transportPeer.address}: $e');
      _recordConnectionFailure(transportPeer.address.value);
    }
  }

  /// Establishes connection to a transport peer.
  Future<PeerConnection> _connectToTransportPeer(
    TransportPeer transportPeer,
  ) async {
    final address = transportPeer.address.value;

    // Check connection limits
    if (_connections.length >= config.maxConnections) {
      throw PeerException(
        'Maximum connections reached (${config.maxConnections})',
      );
    }

    // Record connection attempt
    _recordConnectionAttempt(address);

    try {
      debugPrint(
        '🤝 Connecting to transport peer: ${transportPeer.displayName}',
      );

      // Create transport endpoint for connection
      final endpoint = TransportEndpoint(
        address: address,
        protocol: transportPeer.protocol,
        metadata: transportPeer.metadata,
      );

      // Establish transport connection
      final transportConnection = await transport.connect(endpoint);

      // Perform peer handshake to discover application identity
      final handshakeResult = await handshake.initiate(
        transportConnection,
        config.nodeId,
      );

      // Create application-layer peer
      final peer = Peer(
        id: handshakeResult.peer.id,
        transportPeer: transportPeer,
        metadata: handshakeResult.peer.metadata,
      );

      // Store peer and connection
      _peers[peer.id] = peer;
      _connections[peer.id] = handshakeResult.connection;

      // Clear any failed attempts
      _connectionAttempts.remove(address);
      _lastConnectionAttempt.remove(address);

      // Emit success event
      _emitPeerEvent(PeerConnected(peer: peer, timestamp: DateTime.now()));

      debugPrint('✅ Connected to peer: ${peer.id} (${peer.displayName})');
      return handshakeResult.connection;
    } catch (e) {
      debugPrint(
        '❌ Failed to connect to transport peer ${transportPeer.address}: $e',
      );
      _recordConnectionFailure(address);
      throw ConnectionException('Failed to connect to peer: $e', cause: e);
    }
  }

  /// Schedules periodic discovery.
  void _schedulePeriodicDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(config.discoveryInterval, (_) {
      if (_isDiscoveryActive && !_isDisposed) {
        _triggerDiscovery();
      }
    });
  }

  /// Triggers discovery cycle.
  Future<void> _triggerDiscovery() async {
    try {
      // Restart discovery to find new peers
      if (_isDiscoveryActive) {
        await transport.stopDiscovery();
        await transport.startDiscovery();
      }
    } catch (e) {
      debugPrint('⚠️ Discovery cycle failed: $e');
    }
  }

  /// Schedules health check.
  void _scheduleHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(config.healthCheckInterval, (_) {
      if (!_isDisposed) {
        _performHealthCheck();
      }
    });
  }

  /// Performs health check on all connections.
  Future<void> _performHealthCheck() async {
    final connectionsToCheck = List.of(_connections.entries);

    for (final entry in connectionsToCheck) {
      final peerId = entry.key;
      final connection = entry.value;

      if (!connection.isConnected) {
        continue;
      }

      try {
        await connection.ping().timeout(config.healthCheckTimeout);

        // Update last contact time
        final peer = _peers[peerId];
        if (peer != null) {
          _peers[peerId] = peer.markContacted();
        }
      } catch (e) {
        debugPrint('💔 Health check failed for peer $peerId: $e');

        // Mark peer as unhealthy and potentially disconnect
        await disconnect(peerId);
      }
    }
  }

  /// Records a connection attempt.
  void _recordConnectionAttempt(String address) {
    _connectionAttempts[address] = (_connectionAttempts[address] ?? 0) + 1;
    _lastConnectionAttempt[address] = DateTime.now();
  }

  /// Records a connection failure.
  void _recordConnectionFailure(String address) {
    // Connection attempt counting is handled in _recordConnectionAttempt
    // This method exists for potential future failure-specific logic
  }

  /// Checks if connection is currently in progress.
  bool _isConnectionInProgress(String address) {
    // For simplicity, assume no connection is in progress
    // Real implementation would track ongoing connection attempts
    return false;
  }

  /// Checks if there was a recent failed connection attempt.
  bool _hasRecentFailedAttempt(String address) {
    final attempts = _connectionAttempts[address] ?? 0;
    final lastAttempt = _lastConnectionAttempt[address];

    if (attempts == 0 || lastAttempt == null) return false;

    // Consider recent if within the last reconnect delay period
    final timeSinceLastAttempt = DateTime.now().difference(lastAttempt);
    return timeSinceLastAttempt < config.reconnectDelay;
  }

  /// Checks if reconnection should be attempted.
  bool _shouldAttemptReconnection(String peerId) {
    final attempts = _connectionAttempts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    return attempts < config.maxReconnectAttempts;
  }

  /// Schedules reconnection for a peer.
  void _scheduleReconnection(Peer peer) {
    Timer(config.reconnectDelay, () async {
      if (_isDisposed) return;

      try {
        debugPrint('🔄 Attempting reconnection to peer: ${peer.id}');
        await _connectToTransportPeer(peer.transportPeer);
      } catch (e) {
        debugPrint('❌ Reconnection failed for peer ${peer.id}: $e');
      }
    });
  }

  /// Emits a peer event.
  void _emitPeerEvent(PeerEvent event) {
    if (!_isDisposed) {
      _peerEventsController.add(event);
    }
  }

  /// Disposes of resources.
  void dispose() {
    _isDisposed = true;

    _transportEventsSubscription?.cancel();
    _discoveryTimer?.cancel();
    _healthCheckTimer?.cancel();

    _peerEventsController.close();

    // Don't dispose transport - that's managed by subclass
  }
}

/// Additional peer events specific to discovery.
@immutable
final class PeerDiscoveryStarted {
  const PeerDiscoveryStarted({required this.timestamp});

  final DateTime timestamp;
}

@immutable
final class PeerDiscoveryStopped {
  const PeerDiscoveryStopped({required this.timestamp});

  final DateTime timestamp;
}

// Debug print function - would be replaced with proper logging
void debugPrint(String message) {
  print('[${DateTime.now().toIso8601String()}] $message');
}
