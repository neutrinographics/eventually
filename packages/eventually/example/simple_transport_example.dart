/// Simple example demonstrating the new Transport interface.
///
/// This example shows how to create and use transport implementations
/// in a straightforward way, demonstrating the clean separation of concerns
/// between transport, protocol, and application layers.

import 'dart:async';
import 'dart:typed_data';
import 'package:eventually/eventually.dart';

void main() async {
  print('=== Simple Transport Example ===\n');

  await basicTransportExample();
  print('\n' + '=' * 50 + '\n');
  await peerManagerExample();
}

/// Basic transport usage example
Future<void> basicTransportExample() async {
  print('📡 Basic Transport Usage:');

  // Create a mock transport for demonstration
  final transport = MockTransport();

  // Initialize the transport
  await transport.initialize();
  print('✅ Transport initialized');

  // Set up message handling
  final subscription = transport.incomingBytes.listen((incomingBytes) {
    final message = String.fromCharCodes(incomingBytes.bytes);
    print('📨 Received: $message from ${incomingBytes.peer.displayName}');
  });

  // Add a mock peer
  transport.addMockPeer(
    TransportPeer(
      address: TransportPeerAddress('mock_peer_1'),
      displayName: 'Test Device',
      protocol: 'mock',
    ),
  );

  // Discover peers
  final peers = await transport.discoverPeers();
  print('🔍 Found ${peers.length} peers');

  // Send a message to the first peer
  if (peers.isNotEmpty) {
    final message = Uint8List.fromList('Hello, World!'.codeUnits);
    await transport.sendBytes(peers.first, message);
    print('📤 Sent message to ${peers.first.displayName}');
  }

  // Wait a moment for the message to be processed
  await Future.delayed(Duration(milliseconds: 100));

  // Cleanup
  await subscription.cancel();
  await transport.shutdown();
  print('🛑 Transport shut down');
}

/// Peer manager usage example
Future<void> peerManagerExample() async {
  print('👥 Peer Manager Usage:');

  // Create transport and peer manager
  final transport = MockTransport();
  final config = PeerConfig(
    nodeId: PeerId('example_node'),
    displayName: 'Example Node',
    autoConnect: false, // Manual control for this example
  );

  final peerManager = ModernTransportPeerManager(
    transport: transport,
    config: config,
  );

  // Initialize
  await peerManager.initialize();
  print('✅ Peer manager initialized');

  // Add some mock peers
  transport.addMockPeer(
    TransportPeer(
      address: TransportPeerAddress('peer_1'),
      displayName: 'Alice',
      protocol: 'mock',
    ),
  );

  transport.addMockPeer(
    TransportPeer(
      address: TransportPeerAddress('peer_2'),
      displayName: 'Bob',
      protocol: 'mock',
    ),
  );

  // Start discovery
  await peerManager.startDiscovery();
  print('🔍 Started peer discovery');

  // Wait for discovery
  await Future.delayed(Duration(milliseconds: 200));

  print('👥 Connected peers: ${peerManager.connectedPeers.length}');
  for (final peer in peerManager.connectedPeers) {
    print('  - ${peer.displayName} (${peer.id})');
  }

  // Stop discovery and cleanup
  await peerManager.stopDiscovery();
  await peerManager.dispose();
  print('🛑 Peer manager disposed');
}

/// Mock transport implementation for examples
class MockTransport implements Transport {
  final List<TransportPeer> _mockPeers = [];
  final StreamController<IncomingBytes> _incomingController =
      StreamController<IncomingBytes>.broadcast();
  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  Future<void> shutdown() async {
    _isInitialized = false;
    if (!_incomingController.isClosed) {
      await _incomingController.close();
    }
  }

  @override
  Future<List<TransportPeer>> discoverPeers({Duration? timeout}) async {
    if (!_isInitialized) {
      throw TransportException('Transport not initialized');
    }
    return List.from(_mockPeers);
  }

  @override
  Future<void> sendBytes(
    TransportPeer peer,
    Uint8List bytes, {
    Duration? timeout,
  }) async {
    if (!_isInitialized) {
      throw TransportException('Transport not initialized');
    }

    // Echo the message back as if received from the peer
    final incomingBytes = IncomingBytes(peer, bytes, DateTime.now());
    if (!_incomingController.isClosed) {
      _incomingController.add(incomingBytes);
    }
  }

  @override
  Stream<IncomingBytes> get incomingBytes => _incomingController.stream;

  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async {
    return _mockPeers.any((peer) => peer.address == transportPeer.address);
  }

  /// Add a mock peer for testing
  void addMockPeer(TransportPeer peer) {
    _mockPeers.add(peer);
  }
}

/// Key Benefits of the New Transport Interface:
///
/// 1. **Clean Separation**: Transport layer only handles raw bytes and addresses
/// 2. **Pluggable**: Same application code works with TCP, Nearby, WebSocket, etc.
/// 3. **Testable**: Easy to mock transport for unit tests
/// 4. **Simple API**: Initialize, discover, send/receive, shutdown
/// 5. **Type Safety**: TransportPeer and TransportPeerAddress provide type safety
/// 6. **Async Streams**: Clean reactive programming with incoming bytes stream
///
/// Migration Steps:
/// 1. Replace old TransportManager with concrete Transport implementations
/// 2. Use ModernTransportPeerManager instead of TransportPeerManager
/// 3. Handle incoming bytes through the stream instead of complex callbacks
/// 4. Use TransportPeer instead of TransportEndpoint for peer representation
