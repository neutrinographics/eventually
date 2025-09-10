import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:eventually/eventually.dart';
import 'package:nearby_connections/nearby_connections.dart';

/// PeerManager implementation using Google's Nearby Connections API.
///
/// This implementation uses the separated transport/application architecture:
/// - NearbyTransportManager handles Nearby Connections transport layer
/// - This class manages peer discovery and handshake over those connections
class NearbyConnectionsPeerManager implements PeerManager {
  static const String _serviceId = 'com.eventually.chat';
  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  final String userId;
  final String userName;
  final NearbyTransportManager _transportManager;
  final PeerHandshake _handshake;

  final Map<String, PeerConnection> _peerConnections = {};
  final StreamController<PeerEvent> _peerEventsController =
      StreamController<PeerEvent>.broadcast();

  StreamSubscription? _transportEventsSubscription;
  bool _isDiscoveryActive = false;

  NearbyConnectionsPeerManager({
    required this.userId,
    required this.userName,
    PeerHandshake? handshake,
  }) : _transportManager = NearbyTransportManager(userId, userName),
       _handshake = handshake ?? const DefaultPeerHandshake() {
    _initializeTransportEventHandling();
  }

  @override
  Iterable<Peer> get connectedPeers => _peerConnections.values
      .where((c) => c.isConnected && c.peer != null)
      .map((c) => c.peer!);

  @override
  Stream<PeerEvent> get peerEvents => _peerEventsController.stream;

  @override
  Future<PeerConnection> connectToEndpoint(String endpointAddress) async {
    // Check if we already have a peer connection for this endpoint
    final existingConnection = _peerConnections.values
        .cast<TransportPeerConnection?>()
        .firstWhere(
          (c) => c?.transport.endpoint.address == endpointAddress,
          orElse: () => null,
        );

    if (existingConnection?.isConnected == true &&
        existingConnection?.peer != null) {
      return existingConnection!;
    }

    // Find the transport endpoint
    final endpoint = _transportManager.knownEndpoints.firstWhere(
      (e) => e.address == endpointAddress,
      orElse: () =>
          throw PeerException('Transport endpoint not found: $endpointAddress'),
    );

    try {
      debugPrint('🤝 Connecting to nearby endpoint: $endpointAddress');

      // Establish transport connection
      final transport = await _transportManager.connect(endpoint);

      // Perform peer handshake to discover identity
      final handshakeResult = await _handshake.initiate(transport, userId);

      // Store the peer connection
      _peerConnections[handshakeResult.peer.id] = handshakeResult.connection;

      // Emit peer connected event
      _peerEventsController.add(
        PeerConnected(peer: handshakeResult.peer, timestamp: DateTime.now()),
      );

      debugPrint('✅ Connected to nearby peer: ${handshakeResult.peer.id}');
      return handshakeResult.connection;
    } catch (e) {
      debugPrint('❌ Failed to connect to nearby endpoint $endpointAddress: $e');
      throw ConnectionException('Failed to connect to endpoint: $e', cause: e);
    }
  }

  @override
  PeerConnection? getConnection(String peerId) {
    return _peerConnections[peerId];
  }

  @override
  Future<void> disconnect(String peerId) async {
    final connection = _peerConnections[peerId];
    if (connection != null) {
      await connection.disconnect();
      _peerConnections.remove(peerId);

      final peer = connection.peer;
      if (peer != null) {
        _peerEventsController.add(
          PeerDisconnected(
            peer: peer,
            timestamp: DateTime.now(),
            reason: 'Manual disconnect',
          ),
        );
      }

      debugPrint('👋 Disconnected from nearby peer: $peerId');
    }
  }

  @override
  Future<void> disconnectAll() async {
    final peerIds = List.of(_peerConnections.keys);
    for (final peerId in peerIds) {
      await disconnect(peerId);
    }
    await _transportManager.disconnectAll();
  }

  @override
  Future<void> startDiscovery() async {
    if (_isDiscoveryActive) return;

    _isDiscoveryActive = true;
    debugPrint('🔍 Starting nearby peer discovery');

    // Start transport endpoint discovery
    await _transportManager.startDiscovery();
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isDiscoveryActive) return;

    _isDiscoveryActive = false;
    await _transportManager.stopDiscovery();
    debugPrint('🛑 Stopped nearby peer discovery');
  }

  @override
  Future<List<Peer>> findPeersWithBlock(CID cid) async {
    final peersWithBlock = <Peer>[];

    for (final connection in _peerConnections.values) {
      if (connection.isConnected && connection.peer != null) {
        try {
          final hasBlock = await connection.hasBlock(cid);
          if (hasBlock) {
            peersWithBlock.add(connection.peer!);
          }
        } catch (e) {
          debugPrint(
            '⚠️ Nearby peer ${connection.peer?.id} didn\'t respond to hasBlock query: $e',
          );
        }
      }
    }

    return peersWithBlock;
  }

  @override
  Future<void> broadcast(Message message) async {
    final connections = _peerConnections.values
        .where((c) => c.isConnected)
        .toList();

    for (final connection in connections) {
      try {
        await connection.sendMessage(message);
      } catch (e) {
        debugPrint(
          '⚠️ Failed to broadcast to nearby peer ${connection.peer?.id}: $e',
        );
      }
    }
  }

  @override
  Future<PeerStats> getStats() async {
    final connectedCount = _peerConnections.values
        .where((c) => c.isConnected)
        .length;
    final transportStats = await _transportManager.getStats();

    return PeerStats(
      totalPeers: _peerConnections.length,
      connectedPeers: connectedCount,
      totalMessages: 0, // Would track in a real implementation
      totalBytesReceived: transportStats.totalBytesReceived,
      totalBytesSent: transportStats.totalBytesSent,
      details: {
        'transport_endpoints': transportStats.totalEndpoints,
        'connected_endpoints': transportStats.connectedEndpoints,
        'nearby_connections': true,
      },
    );
  }

  void _initializeTransportEventHandling() {
    _transportEventsSubscription = _transportManager.transportEvents.listen(
      (event) async {
        switch (event) {
          case EndpointDiscovered():
            debugPrint(
              '🔍 Discovered nearby endpoint: ${event.endpoint.address}',
            );
            // Automatically attempt to connect to discovered endpoints
            try {
              await _autoConnectToEndpoint(event.endpoint);
            } catch (e) {
              debugPrint(
                '❌ Auto-connection failed to ${event.endpoint.address}: $e',
              );
            }
            break;

          case TransportConnected():
            debugPrint(
              '🔗 Nearby transport connected: ${event.endpoint.address}',
            );
            break;

          case TransportDisconnected():
            debugPrint(
              '🔌 Nearby transport disconnected: ${event.endpoint.address}',
            );
            await _handleTransportDisconnected(event.endpoint);
            break;

          case TransportDataReceived():
            // Data is handled by individual connections
            break;
        }
      },
      onError: (error) {
        debugPrint('❌ Nearby transport event error: $error');
      },
    );
  }

  Future<void> _handleTransportDisconnected(TransportEndpoint endpoint) async {
    final affectedConnections = _peerConnections.entries
        .where((entry) {
          final connection = entry.value;
          if (connection is TransportPeerConnection) {
            return connection.transport.endpoint.address == endpoint.address;
          }
          return false;
        })
        .map((entry) => entry.key)
        .toList();

    for (final peerId in affectedConnections) {
      await disconnect(peerId);
    }
  }

  /// Automatically attempts to connect to a discovered endpoint
  Future<void> _autoConnectToEndpoint(TransportEndpoint endpoint) async {
    // Skip if we already have a connection attempt in progress
    if (_transportManager.hasConnectionFor(endpoint.address)) {
      debugPrint('⚠️ Connection already exists for: ${endpoint.address}');
      return;
    }

    // Skip if we already have a peer connection for this endpoint
    final existingPeerConnection = _peerConnections.values
        .cast<TransportPeerConnection?>()
        .any((c) => c?.transport.endpoint.address == endpoint.address);

    if (existingPeerConnection) {
      debugPrint('⚠️ Peer already connected for endpoint: ${endpoint.address}');
      return;
    }

    debugPrint('🚀 Auto-connecting to endpoint: ${endpoint.address}');

    try {
      // Attempt to establish peer connection
      await connectToEndpoint(endpoint.address);
    } catch (e) {
      debugPrint('❌ Auto-connection failed for ${endpoint.address}: $e');
      // Don't rethrow - this is a background operation
    }
  }

  void dispose() {
    _transportEventsSubscription?.cancel();
    _peerEventsController.close();
    _transportManager.dispose();
  }
}

/// Transport manager for Google's Nearby Connections API
class NearbyTransportManager implements TransportManager {
  final String userId;
  final String userName;
  final List<TransportEndpoint> _knownEndpoints = [];
  final Map<String, NearbyTransportConnection> _connections = {};
  final StreamController<TransportEvent> _transportEventsController =
      StreamController<TransportEvent>.broadcast();

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  NearbyTransportManager(this.userId, this.userName);

  List<TransportEndpoint> get knownEndpoints =>
      List.unmodifiable(_knownEndpoints);

  @override
  Iterable<TransportEndpoint> get connectedEndpoints =>
      _connections.values.where((c) => c.isConnected).map((c) => c.endpoint);

  /// Check if a connection exists for the given endpoint address
  bool hasConnectionFor(String endpointAddress) {
    return _connections.containsKey(endpointAddress);
  }

  @override
  Stream<TransportEvent> get transportEvents =>
      _transportEventsController.stream;

  @override
  Future<TransportConnection> connect(TransportEndpoint endpoint) async {
    final existingConnection = _connections[endpoint.address];
    if (existingConnection != null && existingConnection.isConnected) {
      return existingConnection;
    }

    final connection = NearbyTransportConnection(endpoint, userId);
    await connection.connect();

    _connections[endpoint.address] = connection;
    _transportEventsController.add(
      TransportConnected(endpoint: endpoint, timestamp: DateTime.now()),
    );

    debugPrint('🔗 Connected to nearby transport: ${endpoint.address}');
    return connection;
  }

  @override
  Future<void> disconnect(String endpointAddress) async {
    final connection = _connections[endpointAddress];
    if (connection != null) {
      await connection.disconnect();
      _connections.remove(endpointAddress);

      _transportEventsController.add(
        TransportDisconnected(
          endpoint: connection.endpoint,
          timestamp: DateTime.now(),
          reason: 'Manual disconnect',
        ),
      );

      debugPrint('🔌 Disconnected from nearby transport: $endpointAddress');
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
  Future<void> startDiscovery() async {
    if (_isAdvertising || _isDiscovering) return;

    try {
      debugPrint('🔍 Starting nearby connections discovery');
      await _startAdvertising();
      await _startDiscovering();
    } catch (e) {
      debugPrint('❌ Failed to start nearby discovery: $e');
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
  Future<TransportStats> getStats() async {
    final totalConnections = _connections.length;
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
        'total_connections': totalConnections,
        'advertising': _isAdvertising,
        'discovering': _isDiscovering,
      },
    );
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;

    await Nearby().startAdvertising(
      userName,
      NearbyConnectionsPeerManager._strategy,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: NearbyConnectionsPeerManager._serviceId,
    );

    _isAdvertising = true;
    debugPrint('📢 Started advertising as: $userName');
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
      userName,
      NearbyConnectionsPeerManager._strategy,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: (String? endpointId) {
        if (endpointId != null) {
          _onEndpointLost(endpointId);
        }
      },
      serviceId: NearbyConnectionsPeerManager._serviceId,
    );

    _isDiscovering = true;
    debugPrint('🔍 Started discovering peers');
  }

  Future<void> _stopDiscovering() async {
    if (!_isDiscovering) return;

    await Nearby().stopDiscovery();
    _isDiscovering = false;
    debugPrint('🔍 Stopped discovering peers');
  }

  void _onEndpointFound(
    String endpointId,
    String endpointName,
    String serviceId,
  ) {
    debugPrint('🔍 Found nearby endpoint: $endpointName ($endpointId)');

    final endpoint = TransportEndpoint(
      address: endpointId,
      protocol: 'nearby_connections',
      metadata: {
        'endpoint_name': endpointName,
        'service_id': serviceId,
        'discovered_at': DateTime.now().toIso8601String(),
      },
    );

    if (!_knownEndpoints.any((e) => e.address == endpointId)) {
      _knownEndpoints.add(endpoint);
      debugPrint('📡 Added new endpoint to known list: $endpointId');

      _transportEventsController.add(
        EndpointDiscovered(endpoint: endpoint, timestamp: DateTime.now()),
      );
    } else {
      debugPrint('⚠️ Endpoint already known: $endpointId');
    }
  }

  void _onEndpointLost(String endpointId) {
    debugPrint('👻 Lost nearby endpoint: $endpointId');
    _knownEndpoints.removeWhere((e) => e.address == endpointId);
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    debugPrint(
      '🤝 Connection initiated with: $endpointId (${info.endpointName})',
    );
    debugPrint('   Authentication token: ${info.authenticationToken}');
    debugPrint('   Is incoming: ${info.isIncomingConnection}');

    // Auto-accept all connections for now
    debugPrint('✅ Auto-accepting connection from: $endpointId');
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) =>
          _handlePayload(endpointId, payload),
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      debugPrint('✅ Connected to nearby endpoint: $endpointId');

      // Update connection state in our transport connections
      final connection = _connections[endpointId];
      if (connection != null) {
        connection._setConnected(true);
      }

      // Emit transport connected event
      final endpoint = _knownEndpoints.firstWhere(
        (e) => e.address == endpointId,
        orElse: () => TransportEndpoint(
          address: endpointId,
          protocol: 'nearby_connections',
          metadata: {'connected_at': DateTime.now().toIso8601String()},
        ),
      );

      _transportEventsController.add(
        TransportConnected(endpoint: endpoint, timestamp: DateTime.now()),
      );
    } else {
      debugPrint(
        '❌ Connection failed to endpoint: $endpointId (Status: $status)',
      );

      // Remove failed connection attempt
      _connections.remove(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    debugPrint('🔌 Disconnected from nearby endpoint: $endpointId');

    // Update connection state
    final connection = _connections[endpointId];
    if (connection != null) {
      connection._setConnected(false);
    }

    // Emit transport disconnected event
    final endpoint = _knownEndpoints.firstWhere(
      (e) => e.address == endpointId,
      orElse: () => TransportEndpoint(
        address: endpointId,
        protocol: 'nearby_connections',
        metadata: {'disconnected_at': DateTime.now().toIso8601String()},
      ),
    );

    _transportEventsController.add(
      TransportDisconnected(
        endpoint: endpoint,
        timestamp: DateTime.now(),
        reason: 'Connection lost',
      ),
    );

    // Clean up
    _connections.remove(endpointId);
  }

  void _handlePayload(String endpointId, Payload payload) {
    final connection = _connections[endpointId];
    if (connection != null) {
      connection._handleIncomingPayload(payload);
    }
  }

  void dispose() {
    _transportEventsController.close();
    disconnectAll();
  }
}

/// Transport connection for Nearby Connections
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
      // Request connection to the endpoint
      await Nearby().requestConnection(
        _localId,
        endpoint.address,
        onConnectionInitiated: (endpointId, info) {
          debugPrint('🔗 Connection initiated with $endpointId');
        },
        onConnectionResult: (endpointId, status) {
          _isConnected = (status == Status.CONNECTED);
          if (_isConnected) {
            debugPrint('✅ Nearby transport connection established');
          } else {
            debugPrint('❌ Nearby transport connection failed');
          }
        },
        onDisconnected: (endpointId) {
          _isConnected = false;
          debugPrint('🔌 Nearby transport connection lost');
        },
      );

      // Wait for connection to be established
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
      // TODO: if the peer is already connected, update it's status and continue.
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

    debugPrint('🔌 Nearby transport disconnected from ${endpoint.address}');
  }

  /// Internal method to update connection state from transport manager
  void _setConnected(bool connected) {
    _isConnected = connected;
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

  void _handleIncomingPayload(Payload payload) {
    if (!_isConnected) return;

    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      final data = payload.bytes!;
      _bytesReceived += data.length;
      _dataController.add(data);
    }
  }
}
