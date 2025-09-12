/// Example showing how to migrate from the old transport interface to the new one.
///
/// This file demonstrates the key differences and provides migration patterns
/// for updating existing code to use the new Transport interface.

import 'dart:async';
import 'dart:typed_data';
import 'package:eventually/eventually.dart';

void main() async {
  print('=== Transport Migration Example ===\n');

  // Show both old and new patterns
  await demonstrateOldPattern();
  print('\n' + '=' * 50 + '\n');
  await demonstrateNewPattern();
}

/// OLD PATTERN (Deprecated)
/// This shows how transport was used with the old interface
Future<void> demonstrateOldPattern() async {
  print('📜 OLD PATTERN (Deprecated)');
  print('Using TransportManager, TransportEndpoint, and TransportConnection\n');

  // Old way: Create endpoints and manage connections manually
  final endpoint = TransportEndpoint(
    address: '192.168.1.100:8080',
    protocol: 'tcp',
    metadata: {'description': 'Chat server'},
  );

  print('Created endpoint: $endpoint');
  print('✗ Had to manage low-level connection lifecycle');
  print('✗ Transport and protocol concerns were mixed');
  print('✗ Complex connection state management');
  print('✗ No clean separation of concerns');
}

/// NEW PATTERN (Recommended)
/// This shows how to use the new Transport interface
Future<void> demonstrateNewPattern() async {
  print('🚀 NEW PATTERN (Recommended)');
  print('Using Transport interface with clean separation of concerns\n');

  // Example 1: TCP Transport
  await demonstrateTcpTransport();

  print('\n' + '-' * 30 + '\n');

  // Example 2: Mock Transport for Testing
  await demonstrateMockTransport();
}

Future<void> demonstrateTcpTransport() async {
  print('📡 TCP Transport Example:');

  // Step 1: Create transport instance
  final transport = TcpTransport(port: 8080, displayName: 'Chat Node');

  // Step 2: Initialize transport
  await transport.initialize();
  print('✅ Transport initialized on port ${transport.localPort}');

  // Step 3: Discover peers
  final discoveredPeers = await transport.discoverPeers(
    timeout: const Duration(seconds: 3),
  );
  print('🔍 Discovered ${discoveredPeers.length} peers');

  // Step 4: Set up message handling
  final subscription = transport.incomingBytes.listen((incomingBytes) {
    final peer = incomingBytes.peer;
    final message = String.fromCharCodes(incomingBytes.bytes);
    print('📨 Received from ${peer.displayName}: $message');
  });

  // Step 5: Send messages to peers
  for (final peer in discoveredPeers) {
    if (await transport.isPeerReachable(peer)) {
      final messageBytes = Uint8List.fromList('Hello from Dart!'.codeUnits);
      await transport.sendBytes(peer, messageBytes);
      print('📤 Sent message to ${peer.displayName}');
    }
  }

  // Step 6: Clean up
  await subscription.cancel();
  await transport.shutdown();
  print('🛑 Transport shut down cleanly');

  print('\n✅ Benefits of new pattern:');
  print('  • Clean separation: transport vs protocol vs application');
  print('  • Simple API: initialize, discover, send/receive, shutdown');
  print('  • Pluggable: same code works with TCP, Nearby, WebSocket, etc.');
  print('  • Testable: easy to mock for unit tests');
}

Future<void> demonstrateMockTransport() async {
  print('🧪 Mock Transport for Testing:');

  final mockTransport = MockTransport();
  await mockTransport.initialize();

  // Mock some discovered peers
  mockTransport.addMockPeer(
    TransportPeer(
      address: TransportPeerAddress('test1'),
      displayName: 'Test Peer 1',
      protocol: 'mock',
    ),
  );

  final peers = await mockTransport.discoverPeers();
  print('🎭 Mock discovered ${peers.length} peers');

  // Test sending/receiving
  final testMessage = Uint8List.fromList('Test message'.codeUnits);
  if (peers.isNotEmpty) {
    await mockTransport.sendBytes(peers.first, testMessage);
    print('📤 Mock sent test message');
  }

  await mockTransport.shutdown();
  print('✅ Mock transport test completed');
}

/// Example Migration Pattern for Existing Code
class MigrationExample {
  /// OLD: How you might have created a peer manager before
  @Deprecated('Use createModernPeerManager instead')
  static Future<String> createOldPeerManager(
    String nodeId,
    String displayName,
  ) async {
    // Old complex setup with multiple classes
    // final config = PeerConfig(nodeId: PeerId(nodeId), displayName: displayName);

    // Had to create transport manager, then peer manager
    // return TransportPeerManager(config: config);
    return 'Old peer manager would be created here';
  }

  /// NEW: Simplified creation with clear dependencies
  static Future<ModernTransportPeerManager> createModernPeerManager(
    String nodeId,
    String displayName, {
    Transport? customTransport,
  }) async {
    // Choose transport implementation
    final transport =
        customTransport ?? TcpTransport(port: 8080, displayName: displayName);

    // Simple, clean configuration
    final config = PeerConfig(
      nodeId: PeerId(nodeId),
      displayName: displayName,
      autoConnect: true,
      maxConnections: 10,
    );

    final peerManager = ModernTransportPeerManager(
      transport: transport,
      config: config,
    );

    await peerManager.initialize();
    return peerManager;
  }
}

/// Key Migration Steps:
///
/// 1. Replace TransportManager with Transport implementations:
///    - TcpTransport for TCP networking
///    - NearbyTransport for Nearby Connections
///    - Custom implementations for other protocols
///
/// 2. Replace TransportEndpoint with TransportPeer:
///    - TransportPeer includes connection state and metadata
///    - TransportPeerAddress is type-safe addressing
///
/// 3. Replace TransportConnection with direct Transport usage:
///    - Transport.sendBytes() for sending data
///    - Transport.incomingBytes stream for receiving data
///    - Transport.isPeerReachable() for health checks
///
/// 4. Use ModernTransportPeerManager instead of TransportPeerManager:
///    - Takes Transport instance as dependency
///    - Cleaner initialization and lifecycle management
///
/// 5. Benefits of migration:
///    - Cleaner separation of concerns
///    - Easier testing with mock transports
///    - More flexible and extensible architecture
///    - Better error handling and connection management

/// Mock transport for testing purposes
class MockTransport implements Transport {
  final List<TransportPeer> _mockPeers = [];
  final StreamController<IncomingBytes> _incomingController =
      StreamController<IncomingBytes>.broadcast();

  @override
  Future<void> initialize() async {
    // Mock initialization
  }

  @override
  Future<void> shutdown() async {
    await _incomingController.close();
  }

  @override
  Future<List<TransportPeer>> discoverPeers({Duration? timeout}) async {
    return List.from(_mockPeers);
  }

  @override
  Future<void> sendBytes(
    TransportPeer peer,
    Uint8List bytes, {
    Duration? timeout,
  }) async {
    // Simulate receiving the message back (echo)
    final incomingBytes = IncomingBytes(peer, bytes, DateTime.now());
    _incomingController.add(incomingBytes);
  }

  @override
  Stream<IncomingBytes> get incomingBytes => _incomingController.stream;

  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async {
    return _mockPeers.contains(transportPeer);
  }

  void addMockPeer(TransportPeer peer) {
    _mockPeers.add(peer);
  }
}
