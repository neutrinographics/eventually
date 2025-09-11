import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' hide debugPrint;
import 'package:eventually/eventually.dart';
import 'package:nearby_connections/nearby_connections.dart';

/// Simplified Nearby Connections peer manager using the transport-based architecture.
///
/// This implementation is dramatically simplified compared to the original,
/// leveraging the base class to handle all the complex peer management logic.
/// It only needs to provide the transport manager and optionally customize behavior.
class NearbyPeerManager extends TransportPeerManager {
  final NearbyTransportManager _transport;

  /// Creates a nearby connections peer manager with the specified configuration.
  NearbyPeerManager({
    required PeerId nodeId,
    required String displayName,
    String serviceId = 'com.eventually.chat',
    Strategy strategy = Strategy.P2P_CLUSTER,
    PeerConfig? config,
    super.handshake,
  }) : _transport = NearbyTransportManager(
         nodeId: nodeId.value,
         displayName: displayName,
         serviceId: serviceId,
         strategy: strategy,
       ),
       super(
         config:
             config ??
             PeerConfig.nearby(nodeId: nodeId, displayName: displayName),
       );

  /// Factory constructor optimized for nearby connections.
  factory NearbyPeerManager.nearby({
    required PeerId nodeId,
    required String displayName,
    String serviceId = 'com.eventually.chat',
  }) {
    return NearbyPeerManager(
      nodeId: nodeId,
      displayName: displayName,
      serviceId: serviceId,
      config: PeerConfig.nearby(nodeId: nodeId, displayName: displayName),
    );
  }

  /// Factory constructor optimized for low latency scenarios.
  factory NearbyPeerManager.lowLatency({
    required PeerId nodeId,
    required String displayName,
    String serviceId = 'com.eventually.chat',
  }) {
    return NearbyPeerManager(
      nodeId: nodeId,
      displayName: displayName,
      serviceId: serviceId,
      config: PeerConfig.lowLatency(nodeId: nodeId, displayName: displayName),
    );
  }

  @override
  TransportManager get transport => _transport;

  @override
  bool shouldAutoConnect(TransportPeer transportPeer) {
    // Only connect to peers with matching service ID
    final serviceId = transportPeer.metadata['service_id'] as String?;
    if (serviceId != _transport.serviceId) {
      return false;
    }

    return super.shouldAutoConnect(transportPeer);
  }

  @override
  Future<void> onTransportPeerDiscovered(TransportPeer transportPeer) async {
    debugPrint(
      '🔍 Discovered nearby peer: ${transportPeer.displayName} with service: ${transportPeer.metadata['service_id']}',
    );
    await super.onTransportPeerDiscovered(transportPeer);
  }

  /// Dispose of resources when no longer needed.
  @override
  void dispose() {
    _transport.dispose();
    super.dispose();
  }
}

/// Simplified transport manager for Nearby Connections.
class NearbyTransportManager implements TransportManager {
  final String nodeId;
  final String displayName;
  final String serviceId;
  final Strategy strategy;

  final List<TransportEndpoint> _knownEndpoints = [];
  final Map<String, NearbyTransportConnection> _connections = {};
  final StreamController<TransportEvent> _eventsController =
      StreamController<TransportEvent>.broadcast();

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  NearbyTransportManager({
    required this.nodeId,
    required this.displayName,
    required this.serviceId,
    required this.strategy,
  });

  @override
  Iterable<TransportEndpoint> get connectedEndpoints =>
      _connections.values.where((c) => c.isConnected).map((c) => c.endpoint);

  @override
  Stream<TransportEvent> get transportEvents => _eventsController.stream;

  @override
  Future<void> startDiscovery() async {
    if (_isAdvertising || _isDiscovering) return;

    try {
      debugPrint('🔍 Starting nearby connections discovery');
      await _startAdvertising();
      await _startDiscovering();
    } catch (e) {
      debugPrint('❌ Failed to start discovery: $e');
      throw TransportException('Failed to start discovery: $e');
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isAdvertising && !_isDiscovering) return;

    debugPrint('🛑 Stopping nearby connections discovery');
    await _stopAdvertising();
    await _stopDiscovering();
  }

  @override
  Future<TransportConnection> connect(TransportEndpoint endpoint) async {
    final existingConnection = _connections[endpoint.address];
    if (existingConnection != null && existingConnection.isConnected) {
      return existingConnection;
    }

    final connection = NearbyTransportConnection(endpoint, nodeId);
    await connection.connect();

    _connections[endpoint.address] = connection;
    _eventsController.add(
      TransportConnected(endpoint: endpoint, timestamp: DateTime.now()),
    );

    debugPrint('🔗 Connected to transport: ${endpoint.address}');
    return connection;
  }

  @override
  Future<void> disconnect(String endpointAddress) async {
    final connection = _connections[endpointAddress];
    if (connection != null) {
      await connection.disconnect();
      _connections.remove(endpointAddress);

      _eventsController.add(
        TransportDisconnected(
          endpoint: connection.endpoint,
          timestamp: DateTime.now(),
          reason: 'Manual disconnect',
        ),
      );
    }
  }

  @override
  Future<void> disconnectAll() async {
    final connections = List.of(_connections.values);
    for (final connection in connections) {
      await disconnect(connection.endpoint.address);
    }

    await _stopAdvertising();
    await _stopDiscovering();
  }

  @override
  Future<TransportStats> getStats() async {
    final activeConnections = _connections.values
        .where((c) => c.isConnected)
        .length;

    int totalBytesReceived = 0;
    int totalBytesSent = 0;

    for (final connection in _connections.values) {
      totalBytesReceived += connection.bytesReceived;
      totalBytesSent += connection.bytesSent;
    }

    return TransportStats(
      totalEndpoints: _knownEndpoints.length,
      connectedEndpoints: activeConnections,
      totalBytesReceived: totalBytesReceived,
      totalBytesSent: totalBytesSent,
      protocolStats: {
        'nearby_connections': true,
        'advertising': _isAdvertising,
        'discovering': _isDiscovering,
        'service_id': serviceId,
        'strategy': strategy.toString(),
      },
    );
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;

    await Nearby().startAdvertising(
      displayName,
      strategy,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: serviceId,
    );

    _isAdvertising = true;
    debugPrint('📢 Started advertising as: $displayName');
  }

  Future<void> _stopAdvertising() async {
    if (!_isAdvertising) return;

    await Nearby().stopAdvertising();
    _isAdvertising = false;
    debugPrint('🔇 Stopped advertising');
  }

  Future<void> _startDiscovering() async {
    if (_isDiscovering) return;

    await Nearby().startDiscovery(
      displayName,
      strategy,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: (String? endpointId) {
        if (endpointId != null) {
          _onEndpointLost(endpointId);
        }
      },
      serviceId: serviceId,
    );

    _isDiscovering = true;
    debugPrint('🔍 Started discovering peers');
  }

  Future<void> _stopDiscovering() async {
    if (!_isDiscovering) return;

    await Nearby().stopDiscovery();
    _isDiscovering = false;
  }

  void _onEndpointFound(
    String endpointId,
    String endpointName,
    String foundServiceId,
  ) {
    debugPrint(
      '🔍 Found endpoint: $endpointName ($endpointId) - Service: $foundServiceId',
    );

    final endpoint = TransportEndpoint(
      address: endpointId,
      protocol: 'nearby_connections',
      metadata: {
        'endpoint_name': endpointName,
        'service_id': foundServiceId,
        'discovered_at': DateTime.now().toIso8601String(),
      },
    );

    if (!_knownEndpoints.any((e) => e.address == endpointId)) {
      _knownEndpoints.add(endpoint);
      _eventsController.add(
        EndpointDiscovered(endpoint: endpoint, timestamp: DateTime.now()),
      );
    }
  }

  void _onEndpointLost(String endpointId) {
    debugPrint('👻 Lost endpoint: $endpointId');
    _knownEndpoints.removeWhere((e) => e.address == endpointId);
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    debugPrint(
      '🤝 Connection initiated with: $endpointId (${info.endpointName})',
    );

    // Auto-accept all connections
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) =>
          _handlePayload(endpointId, payload),
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      debugPrint('✅ Connected to endpoint: $endpointId');

      // Update connection state
      final connection = _connections[endpointId];
      if (connection != null) {
        connection.setConnected(true);
      }

      // Find and emit transport connected event
      final endpoint = _knownEndpoints.firstWhere(
        (e) => e.address == endpointId,
        orElse: () => TransportEndpoint(
          address: endpointId,
          protocol: 'nearby_connections',
          metadata: {'connected_at': DateTime.now().toIso8601String()},
        ),
      );

      _eventsController.add(
        TransportConnected(endpoint: endpoint, timestamp: DateTime.now()),
      );
    } else {
      debugPrint(
        '❌ Connection failed to endpoint: $endpointId (Status: $status)',
      );
      _connections.remove(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    debugPrint('🔌 Disconnected from endpoint: $endpointId');

    final connection = _connections[endpointId];
    if (connection != null) {
      connection.setConnected(false);

      _eventsController.add(
        TransportDisconnected(
          endpoint: connection.endpoint,
          timestamp: DateTime.now(),
          reason: 'Connection lost',
        ),
      );
    }

    _connections.remove(endpointId);
  }

  void _handlePayload(String endpointId, Payload payload) {
    final connection = _connections[endpointId];
    if (connection != null) {
      connection.handleIncomingPayload(payload);
    }
  }

  void dispose() {
    _eventsController.close();
    disconnectAll();
  }
}

/// Simplified transport connection for Nearby Connections.
class NearbyTransportConnection implements TransportConnection {
  final TransportEndpoint _endpoint;
  final String _localId;
  final StreamController<List<int>> _dataController =
      StreamController<List<int>>.broadcast();

  bool _isConnected = false;
  int _bytesReceived = 0;
  int _bytesSent = 0;

  NearbyTransportConnection(this._endpoint, this._localId);

  @override
  TransportEndpoint get endpoint => _endpoint;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<List<int>> get dataStream => _dataController.stream;

  int get bytesReceived => _bytesReceived;
  int get bytesSent => _bytesSent;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      await Nearby().requestConnection(
        _localId,
        endpoint.address,
        onConnectionInitiated: (endpointId, info) {
          debugPrint('🔗 Connection initiated with $endpointId');
        },
        onConnectionResult: (endpointId, status) {
          _isConnected = (status == Status.CONNECTED);
          if (_isConnected) {
            debugPrint('✅ Transport connection established');
          } else {
            debugPrint('❌ Transport connection failed');
          }
        },
        onDisconnected: (endpointId) {
          _isConnected = false;
          debugPrint('🔌 Transport connection lost');
        },
      );

      // Wait for connection
      int attempts = 0;
      while (!_isConnected && attempts < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      if (!_isConnected) {
        throw TransportConnectionException(
          'Connection timeout',
          endpoint: endpoint,
        );
      }
    } catch (e) {
      throw TransportConnectionException(
        'Failed to connect: $e',
        endpoint: endpoint,
        cause: e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected) return;

    await Nearby().disconnectFromEndpoint(endpoint.address);
    _isConnected = false;
    await _dataController.close();
  }

  @override
  Future<void> sendData(List<int> data) async {
    if (!_isConnected) {
      throw TransportConnectionException(
        'Cannot send data: not connected',
        endpoint: endpoint,
      );
    }

    _bytesSent += data.length;
    final bytes = Uint8List.fromList(data);
    await Nearby().sendBytesPayload(endpoint.address, bytes);
  }

  @override
  Map<String, dynamic> getConnectionInfo() {
    return {
      'endpoint': endpoint.address,
      'protocol': endpoint.protocol,
      'connected': _isConnected,
      'bytes_sent': _bytesSent,
      'bytes_received': _bytesReceived,
      'local_id': _localId,
      'endpoint_metadata': endpoint.metadata,
    };
  }

  /// Internal method to update connection state.
  void setConnected(bool connected) {
    _isConnected = connected;
  }

  /// Handles incoming payload data.
  void handleIncomingPayload(Payload payload) {
    if (!_isConnected) return;

    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final data = payload.bytes!;
      _bytesReceived += data.length;
      _dataController.add(data);
    }
  }
}
