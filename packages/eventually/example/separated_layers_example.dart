import 'dart:async';
import 'dart:typed_data';
import 'package:eventually/eventually.dart';

/// Example demonstrating the separated transport and application layer architecture.
///
/// This example shows how:
/// 1. Transport endpoints are discovered and connected to at the transport layer
/// 2. Peer identity is discovered through handshake after transport connection
/// 3. Application-layer communication happens after peer identity is established
void main() async {
  print('🚀 Starting separated layers example...\n');

  // Create two mock peer managers to simulate different nodes
  final peerManager1 = MockPeerManager(userId: 'alice');
  final peerManager2 = MockPeerManager(userId: 'bob');

  try {
    // Step 1: Start discovery on both peers
    print('📡 Starting peer discovery...');
    await peerManager1.startDiscovery();
    await peerManager2.startDiscovery();

    // Wait a moment for transport endpoints to be discovered
    await Future.delayed(const Duration(seconds: 2));

    // Step 2: Get discovered transport endpoints
    final endpoints1 = peerManager1.transportManager.knownEndpoints;
    final endpoints2 = peerManager2.transportManager.knownEndpoints;

    print('🔍 Peer 1 discovered ${endpoints1.length} transport endpoints:');
    for (final endpoint in endpoints1) {
      print('  - ${endpoint.protocol}://${endpoint.address}');
    }

    print('🔍 Peer 2 discovered ${endpoints2.length} transport endpoints:');
    for (final endpoint in endpoints2) {
      print('  - ${endpoint.protocol}://${endpoint.address}');
    }

    // Step 3: Connect to a transport endpoint (this triggers peer handshake)
    if (endpoints1.isNotEmpty) {
      print(
        '\n🤝 Connecting to transport endpoint: ${endpoints1.first.address}',
      );

      try {
        // This will:
        // 1. Establish transport connection
        // 2. Perform peer handshake to discover identity
        // 3. Return application-layer peer connection
        final connection = await peerManager2.connectToEndpoint(
          endpoints1.first.address,
        );

        final discoveredPeer = connection.peer;
        print('✅ Successfully connected to peer: ${discoveredPeer?.id}');
        print('   Transport endpoint: ${endpoints1.first.address}');
        print('   Application peer ID: ${discoveredPeer?.id}');

        // Step 4: Use the peer connection for application-layer communication
        if (discoveredPeer != null) {
          print('\n💬 Testing application-layer communication...');

          // Send a ping message
          final latency = await connection.ping();
          print('🏓 Ping successful! Latency: ${latency.inMilliseconds}ms');

          // Get peer capabilities
          final capabilities = await connection.getCapabilities();
          print('🔧 Peer capabilities: ${capabilities.join(', ')}');

          // Test block operations
          print('\n📦 Testing block operations...');

          // Create a test block
          final testData = 'Hello from ${discoveredPeer.id}!';
          final block = Block.fromData(Uint8List.fromList(testData.codeUnits));

          // Send the block to the peer
          await connection.sendBlock(block);
          print('📤 Sent block ${block.cid} to peer');

          // Check if peer has the block
          final hasBlock = await connection.hasBlock(block.cid);
          print('📥 Peer has block: $hasBlock');
        }

        // Step 5: Demonstrate separation of concerns
        print('\n🏗️ Architecture Summary:');
        print('├── Transport Layer:');
        print('│   ├── Endpoint: ${endpoints1.first.address}');
        print('│   ├── Protocol: ${endpoints1.first.protocol}');
        print('│   └── Connection: Active');
        print('└── Application Layer:');
        print('    ├── Peer ID: ${discoveredPeer?.id}');
        print('    ├── Metadata: ${discoveredPeer?.metadata}');
        print('    └── Communication: Ready');
      } catch (e) {
        print('❌ Connection failed: $e');
      }
    } else {
      print('⚠️ No transport endpoints discovered');
    }

    // Step 6: Show peer statistics
    print('\n📊 Final Statistics:');

    final stats1 = await peerManager1.getStats();
    print('Peer 1 (${peerManager1.userId}):');
    print('  Connected peers: ${stats1.connectedPeers}');
    print('  Total bytes sent: ${stats1.totalBytesSent}');
    print('  Total bytes received: ${stats1.totalBytesReceived}');

    final stats2 = await peerManager2.getStats();
    print('Peer 2 (${peerManager2.userId}):');
    print('  Connected peers: ${stats2.connectedPeers}');
    print('  Total bytes sent: ${stats2.totalBytesSent}');
    print('  Total bytes received: ${stats2.totalBytesReceived}');
  } finally {
    // Cleanup
    await peerManager1.disconnectAll();
    await peerManager2.disconnectAll();
    peerManager1.dispose();
    peerManager2.dispose();
    print('\n🧹 Cleanup complete');
  }

  print('\n✅ Example completed successfully!');
  print('\nKey takeaways:');
  print('• Transport endpoints are discovered without knowing peer identity');
  print(
    '• Peer identity is learned through handshake after transport connection',
  );
  print('• Application layer is completely separate from transport concerns');
  print('• Peers can communicate using logical IDs, not transport addresses');
}

/// Mock implementation for the example
class MockPeerManager implements PeerManager {
  final String userId;
  final MockTransportManager transportManager;
  final Map<String, PeerConnection> _connections = {};
  final StreamController<PeerEvent> _eventsController =
      StreamController.broadcast();

  MockPeerManager({required this.userId})
    : transportManager = MockTransportManager(userId);

  @override
  Iterable<Peer> get connectedPeers => _connections.values
      .where((c) => c.isConnected && c.peer != null)
      .map((c) => c.peer!);

  @override
  Stream<PeerEvent> get peerEvents => _eventsController.stream;

  @override
  Future<PeerConnection> connectToEndpoint(String endpointAddress) async {
    // Simulate finding the endpoint
    final endpoint = TransportEndpoint(
      address: endpointAddress,
      protocol: 'mock_tcp',
      metadata: {},
    );

    // Establish transport connection
    final transport = await transportManager.connect(endpoint);

    // Perform handshake to discover peer identity
    final handshake = DefaultPeerHandshake();
    final result = await handshake.initiate(transport, userId);

    // Store connection
    _connections[result.peer.id] = result.connection;

    // Emit event
    _eventsController.add(
      PeerConnected(peer: result.peer, timestamp: DateTime.now()),
    );

    return result.connection;
  }

  @override
  PeerConnection? getConnection(String peerId) => _connections[peerId];

  @override
  Future<void> disconnect(String peerId) async {
    final connection = _connections.remove(peerId);
    if (connection != null) {
      await connection.disconnect();
      final peer = connection.peer;
      if (peer != null) {
        _eventsController.add(
          PeerDisconnected(peer: peer, timestamp: DateTime.now()),
        );
      }
    }
  }

  @override
  Future<void> disconnectAll() async {
    final peerIds = List.of(_connections.keys);
    for (final peerId in peerIds) {
      await disconnect(peerId);
    }
    await transportManager.disconnectAll();
  }

  @override
  Future<void> startDiscovery() => transportManager.startDiscovery();

  @override
  Future<void> stopDiscovery() => transportManager.stopDiscovery();

  @override
  Future<List<Peer>> findPeersWithBlock(CID cid) async {
    return connectedPeers.toList(); // Simplified for example
  }

  @override
  Future<void> broadcast(Message message) async {
    for (final connection in _connections.values) {
      if (connection.isConnected) {
        await connection.sendMessage(message);
      }
    }
  }

  @override
  Future<PeerStats> getStats() async {
    final transportStats = await transportManager.getStats();
    return PeerStats(
      totalPeers: _connections.length,
      connectedPeers: connectedPeers.length,
      totalMessages: 0,
      totalBytesReceived: transportStats.totalBytesReceived,
      totalBytesSent: transportStats.totalBytesSent,
    );
  }

  void dispose() {
    _eventsController.close();
    transportManager.dispose();
  }
}

/// Simple mock transport manager for the example
class MockTransportManager implements TransportManager {
  final String localId;
  final List<TransportEndpoint> _endpoints = [];
  final StreamController<TransportEvent> _eventsController =
      StreamController.broadcast();

  MockTransportManager(this.localId);

  List<TransportEndpoint> get knownEndpoints => List.unmodifiable(_endpoints);

  @override
  Iterable<TransportEndpoint> get connectedEndpoints => _endpoints;

  @override
  Stream<TransportEvent> get transportEvents => _eventsController.stream;

  @override
  Future<TransportConnection> connect(TransportEndpoint endpoint) async {
    return MockTransportConnection(endpoint);
  }

  @override
  Future<void> disconnect(String endpointAddress) async {}

  @override
  Future<void> disconnectAll() async {}

  @override
  Future<void> startDiscovery() async {
    // Simulate discovering some endpoints
    await Future.delayed(const Duration(milliseconds: 500));

    final endpoint1 = TransportEndpoint(
      address: '192.168.1.100:8080',
      protocol: 'mock_tcp',
      metadata: {'discovered_at': DateTime.now().toIso8601String()},
    );

    final endpoint2 = TransportEndpoint(
      address: '192.168.1.101:8080',
      protocol: 'mock_tcp',
      metadata: {'discovered_at': DateTime.now().toIso8601String()},
    );

    _endpoints.addAll([endpoint1, endpoint2]);

    _eventsController.add(
      EndpointDiscovered(endpoint: endpoint1, timestamp: DateTime.now()),
    );
    _eventsController.add(
      EndpointDiscovered(endpoint: endpoint2, timestamp: DateTime.now()),
    );
  }

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<TransportStats> getStats() async {
    return const TransportStats(
      totalEndpoints: 2,
      connectedEndpoints: 1,
      totalBytesReceived: 1024,
      totalBytesSent: 768,
    );
  }

  void dispose() {
    _eventsController.close();
  }
}

/// Mock transport connection for the example
class MockTransportConnection implements TransportConnection {
  final TransportEndpoint _endpoint;
  final StreamController<List<int>> _dataController =
      StreamController.broadcast();
  bool _connected = false;

  MockTransportConnection(this._endpoint);

  @override
  TransportEndpoint get endpoint => _endpoint;

  @override
  bool get isConnected => _connected;

  @override
  Stream<List<int>> get dataStream => _dataController.stream;

  @override
  Future<void> connect() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _dataController.close();
  }

  @override
  Future<void> sendData(List<int> data) async {
    if (!_connected) throw TransportConnectionException('Not connected');

    // Simulate echoing back a handshake response
    await Future.delayed(const Duration(milliseconds: 50));
    final response =
        '{"type":"response","peer_id":"mock_peer_123","metadata":{"name":"Mock Peer"}}'
            .codeUnits;
    _dataController.add(response);
  }

  @override
  Map<String, dynamic> getConnectionInfo() {
    return {
      'endpoint': endpoint.address,
      'protocol': endpoint.protocol,
      'connected': _connected,
    };
  }
}
