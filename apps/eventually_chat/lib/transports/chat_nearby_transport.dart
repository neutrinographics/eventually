import 'dart:async';
import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart' as nc;
import 'package:meta/meta.dart';
import 'package:eventually/eventually.dart';

/// Chat-specific Nearby Connections transport implementation.
///
/// This transport is optimized for the Eventually Chat app, with specific
/// configurations and error handling suitable for chat applications.
class ChatNearbyTransport implements Transport {
  /// The local node identifier (typically user ID).
  final String nodeId;

  /// Display name shown to other users during discovery.
  final String displayName;

  /// Service ID for the chat app.
  final String serviceId;

  /// Connection strategy for nearby connections.
  final nc.Strategy strategy;

  // Internal state
  bool _isInitialized = false;
  bool _isAdvertising = false;
  bool _isDiscovering = false;

  final Map<String, TransportPeer> _discoveredPeers = {};
  final Map<String, TransportPeer> _connectedPeers = {};
  final StreamController<IncomingBytes> _incomingBytesController =
      StreamController<IncomingBytes>.broadcast();

  /// Creates a chat nearby transport with the specified configuration.
  ChatNearbyTransport({
    required this.nodeId,
    required this.displayName,
    this.serviceId = 'com.eventually.chat',
    this.strategy = nc.Strategy.P2P_CLUSTER,
  });

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request necessary permissions
      final granted = await nc.Nearby()
          .askLocationAndExternalStoragePermission();
      if (!granted) {
        throw const TransportException(
          'Location and storage permissions are required for chat functionality',
        );
      }

      // Start advertising with chat-specific configuration
      await nc.Nearby().startAdvertising(
        displayName,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );

      // Start discovery
      await nc.Nearby().startDiscovery(
        serviceId,
        strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
      );

      _isAdvertising = true;
      _isDiscovering = true;
      _isInitialized = true;

      print('🚀 Chat transport initialized - advertising as "$displayName"');
    } catch (e) {
      throw TransportException(
        'Failed to initialize chat nearby transport',
        cause: e,
      );
    }
  }

  @override
  Future<void> shutdown() async {
    if (!_isInitialized) return;

    try {
      print('🛑 Shutting down chat transport');

      if (_isAdvertising) {
        await nc.Nearby().stopAdvertising();
        _isAdvertising = false;
      }

      if (_isDiscovering) {
        await nc.Nearby().stopDiscovery();
        _isDiscovering = false;
      }

      // Disconnect from all peers
      final disconnectFutures = _connectedPeers.keys.map((endpointId) async {
        try {
          await Nearby().disconnectFromEndpoint(endpointId);
        } catch (e) {
          print('Error disconnecting from $endpointId: $e');
        }
      });

      await Future.wait(disconnectFutures);

      _connectedPeers.clear();
      _discoveredPeers.clear();
      _isInitialized = false;

      if (!_incomingBytesController.isClosed) {
        await _incomingBytesController.close();
      }

      print('✅ Chat transport shutdown complete');
    } catch (e) {
      throw TransportException(
        'Failed to shutdown chat nearby transport',
        cause: e,
      );
    }
  }

  @override
  Future<List<TransportPeer>> discoverPeers({Duration? timeout}) async {
    if (!_isInitialized) {
      throw const TransportException('Transport not initialized');
    }

    print('🔍 Discovering chat peers...');

    // Restart discovery to get fresh results
    if (_isDiscovering) {
      await nc.Nearby().stopDiscovery();
    }

    await nc.Nearby().startDiscovery(
      serviceId,
      strategy,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: _onEndpointLost,
    );

    _isDiscovering = true;

    // Wait for discovery timeout or use default
    final discoveryTimeout = timeout ?? const Duration(seconds: 8);
    await Future.delayed(discoveryTimeout);

    final discovered = _discoveredPeers.values.toList();
    print('📱 Found ${discovered.length} chat peers');

    return discovered;
  }

  @override
  Future<void> sendBytes(
    TransportPeer peer,
    Uint8List bytes, {
    Duration? timeout,
  }) async {
    if (!_isInitialized) {
      throw const TransportException('Transport not initialized');
    }

    final connectedPeer = _connectedPeers[peer.address.value];
    if (connectedPeer == null) {
      throw TransportException('Not connected to peer: ${peer.displayName}');
    }

    try {
      await nc.Nearby().sendBytesPayload(peer.address.value, bytes);
    } catch (e) {
      throw TransportException(
        'Failed to send message to ${peer.displayName}',
        cause: e,
      );
    }
  }

  @override
  Stream<IncomingBytes> get incomingBytes => _incomingBytesController.stream;

  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async {
    if (!_isInitialized) return false;

    // Check if we have an active connection to this peer
    final connectedPeer = _connectedPeers[transportPeer.address.value];
    return connectedPeer != null && connectedPeer.isActive;
  }

  /// Manually connect to a discovered peer.
  ///
  /// This is useful for initiating chat connections to specific users.
  Future<void> connectToPeer(TransportPeer peer) async {
    if (!_isInitialized) {
      throw const TransportException('Transport not initialized');
    }

    if (_connectedPeers.containsKey(peer.address.value)) {
      return; // Already connected
    }

    try {
      print('🤝 Connecting to ${peer.displayName}...');

      await nc.Nearby().requestConnection(
        displayName,
        peer.address.value,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      throw TransportException(
        'Failed to connect to ${peer.displayName}',
        cause: e,
      );
    }
  }

  // Private callback methods for Nearby Connections

  void _onEndpointFound(
    String endpointId,
    String endpointName,
    String serviceId,
  ) {
    print('👋 Found chat user: $endpointName');

    final peer = TransportPeer(
      address: TransportPeerAddress(endpointId),
      displayName: endpointName,
      protocol: 'nearby_connections',
      metadata: {
        'service_id': serviceId,
        'endpoint_id': endpointId,
        'discovered_at': DateTime.now().toIso8601String(),
        'app_type': 'eventually_chat',
      },
    );

    _discoveredPeers[endpointId] = peer;
  }

  void _onEndpointLost(String endpointId) {
    final peer = _discoveredPeers[endpointId];
    if (peer != null) {
      print('👋 Lost chat user: ${peer.displayName}');
      _discoveredPeers.remove(endpointId);
    }

    // Also update connected peers if it was connected
    final connectedPeer = _connectedPeers[endpointId];
    if (connectedPeer != null) {
      _connectedPeers[endpointId] = connectedPeer.copyWith(isActive: false);
    }
  }

  void _onConnectionInitiated(
    String endpointId,
    nc.ConnectionInfo connectionInfo,
  ) {
    final peer = _discoveredPeers[endpointId];
    final peerName = peer?.displayName ?? 'Unknown User';

    print('🤝 Connection initiated with $peerName');

    // Auto-accept all connection requests for the chat app
    // In a production app, you might want to show a dialog
    nc.Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: _onPayloadTransferUpdate,
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    final peer = _discoveredPeers[endpointId];
    final peerName = peer?.displayName ?? 'Unknown User';

    if (status == Status.CONNECTED) {
      print('✅ Connected to $peerName');

      final connectedPeer = (peer ?? _createUnknownPeer(endpointId)).copyWith(
        isActive: true,
        connectedAt: DateTime.now(),
        metadata: {
          ...(peer?.metadata ?? {}),
          'connected_at': DateTime.now().toIso8601String(),
          'status': 'connected',
        },
      );

      _connectedPeers[endpointId] = connectedPeer;
    } else {
      print('❌ Failed to connect to $peerName: $status');
      _connectedPeers.remove(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    final peer = _connectedPeers[endpointId];
    if (peer != null) {
      print('👋 Disconnected from ${peer.displayName}');
      _connectedPeers[endpointId] = peer.copyWith(isActive: false);
    }
  }

  void _onPayloadReceived(String endpointId, nc.Payload payload) {
    final peer = _connectedPeers[endpointId];
    if (peer != null && payload.bytes != null) {
      final incomingBytes = IncomingBytes(
        peer,
        Uint8List.fromList(payload.bytes!),
        DateTime.now(),
      );

      if (!_incomingBytesController.isClosed) {
        _incomingBytesController.add(incomingBytes);
      }
    }
  }

  void _onPayloadTransferUpdate(
    String endpointId,
    nc.PayloadTransferUpdate update,
  ) {
    // Handle payload transfer updates if needed
    // This could be used for progress tracking on large file transfers
  }

  TransportPeer _createUnknownPeer(String endpointId) {
    return TransportPeer(
      address: TransportPeerAddress(endpointId),
      displayName: 'Unknown User',
      protocol: 'nearby_connections',
      metadata: {
        'connected_at': DateTime.now().toIso8601String(),
        'status': 'connected',
        'app_type': 'eventually_chat',
      },
    );
  }

  /// Gets all currently connected chat users.
  List<TransportPeer> get connectedPeers =>
      _connectedPeers.values.where((peer) => peer.isActive).toList();

  /// Gets all discovered chat users (connected and not connected).
  List<TransportPeer> get discoveredPeers => _discoveredPeers.values.toList();

  /// Gets the number of connected chat users.
  int get connectedUserCount => connectedPeers.length;

  /// Checks if the transport is ready for chat operations.
  bool get isReady => _isInitialized && _isAdvertising && _isDiscovering;
}
