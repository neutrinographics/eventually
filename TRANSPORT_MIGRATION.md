# Transport Layer Migration Guide

This document explains the migration from the legacy transport interface to the new, cleaner Transport interface in the Eventually library.

## Overview

The Eventually library has been refactored to provide a cleaner separation between transport, protocol, and application layers. The new architecture offers better testability, modularity, and extensibility.

## Key Benefits

### 🎯 Clean Separation of Concerns
- **Transport Layer**: Only handles raw bytes and network connectivity
- **Protocol Layer**: Handles message encoding/decoding and sync protocols  
- **Application Layer**: Handles business logic and data structures

### 🔧 Pluggable Architecture
- Same application code works with TCP, Nearby Connections, WebSocket, etc.
- Easy to add new transport implementations
- Transport-agnostic sync and protocol logic

### 🧪 Improved Testability
- Easy to mock transport layer for unit tests
- Clear interfaces make testing each layer in isolation simple
- Deterministic behavior in tests

### 🚀 Simplified API
- Fewer classes and interfaces to learn
- Clear lifecycle management (initialize → discover → send/receive → shutdown)
- Reactive programming with streams

## Architecture Comparison

### Old Architecture (Deprecated)
```
Application Layer
├── PeerManager
├── Synchronizer
└── DAG Operations
        ↕
Protocol Layer (Mixed)
├── TransportPeerManager
├── TransportManager (Abstract)
├── TransportConnection (Abstract)  
└── TransportEndpoint
        ↕
Transport Implementations
├── NearbyTransportManager
├── NearbyTransportConnection
└── Concrete implementations
```

### New Architecture (Recommended)
```
Application Layer
├── Peer, PeerId, Block, DAG
├── ChatMessage, UserPresence
└── Business Logic
        ↕
Protocol Layer  
├── Synchronizer
├── SyncProtocol (BitSwap, etc.)
├── Message types (BlockRequest, etc.)
└── ModernTransportPeerManager
        ↕
Transport Layer (Clean Interface)
├── Transport (interface)
├── TransportPeer, TransportPeerAddress
├── IncomingBytes stream
└── Concrete implementations:
    ├── TcpTransport
    ├── NearbyTransport
    └── ChatNearbyTransport
```

## Migration Steps

### 1. Replace Transport Classes

**Old Code:**
```dart
// Old: Complex transport management
final transportManager = NearbyTransportManager(
  nodeId: nodeId,
  displayName: displayName,
  serviceId: serviceId,
);

final peerManager = TransportPeerManager(
  config: config,
  transport: transportManager,
);
```

**New Code:**
```dart
// New: Simple transport creation
final transport = ChatNearbyTransport(
  nodeId: nodeId,
  displayName: displayName,
  serviceId: serviceId,
);

final peerManager = ModernTransportPeerManager(
  transport: transport,
  config: config,
);
```

### 2. Update Peer Discovery

**Old Code:**
```dart
// Old: Manual endpoint management
final endpoints = await transportManager.discoverEndpoints();
for (final endpoint in endpoints) {
  final connection = await transportManager.connect(endpoint);
  // Complex connection lifecycle management
}
```

**New Code:**
```dart
// New: Simple peer discovery
final peers = await transport.discoverPeers();
for (final peer in peers) {
  final reachable = await transport.isPeerReachable(peer);
  if (reachable) {
    // Peer manager handles connection lifecycle automatically
  }
}
```

### 3. Update Message Handling

**Old Code:**
```dart
// Old: Complex callback-based message handling
connection.dataStream.listen((data) {
  // Manual parsing and routing
  final message = parseMessage(data);
  handleMessage(message);
});
```

**New Code:**
```dart
// New: Clean stream-based message handling
transport.incomingBytes.listen((incomingBytes) {
  final peer = incomingBytes.peer;
  final data = incomingBytes.bytes;
  // Clean separation - transport only provides raw bytes
});
```

### 4. Update Service Initialization

**Old Code:**
```dart
// Old: Complex initialization sequence
class OldChatService {
  late final NearbyPeerManager _peerManager;
  
  Future<void> initialize() async {
    _peerManager = NearbyPeerManager(
      nodeId: PeerId(userId),
      displayName: userName,
      serviceId: 'com.eventually.chat',
      strategy: Strategy.P2P_CLUSTER,
      config: config,
    );
    
    // Complex setup with multiple managers
    await _peerManager.initialize();
  }
}
```

**New Code:**
```dart
// New: Clean initialization with dependency injection
class ModernChatService {
  late final ChatNearbyTransport _transport;
  late final ModernTransportPeerManager _peerManager;
  
  Future<void> initialize() async {
    // Clean separation of concerns
    _transport = ChatNearbyTransport(
      nodeId: userId,
      displayName: userName,
      serviceId: 'com.eventually.chat',
    );
    
    _peerManager = ModernTransportPeerManager(
      transport: _transport,
      config: config,
    );
    
    await _peerManager.initialize();
  }
}
```

## Creating Custom Transports

The new architecture makes it easy to create custom transport implementations:

```dart
class MyCustomTransport implements Transport {
  @override
  Future<void> initialize() async {
    // Initialize your transport (open sockets, start services, etc.)
  }
  
  @override
  Future<List<TransportPeer>> discoverPeers({Duration? timeout}) async {
    // Implement peer discovery for your transport
    return discoveredPeers;
  }
  
  @override
  Future<void> sendBytes(TransportPeer peer, Uint8List bytes, {Duration? timeout}) async {
    // Send raw bytes to the peer
  }
  
  @override
  Stream<IncomingBytes> get incomingBytes => _incomingController.stream;
  
  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async {
    // Check if peer is reachable
    return true;
  }
  
  @override
  Future<void> shutdown() async {
    // Clean shutdown
  }
}
```

## Testing Improvements

### Old Testing (Difficult)
```dart
// Old: Hard to test due to tight coupling
testWidgets('chat service test', (tester) async {
  // Had to mock complex transport manager hierarchy
  final mockTransportManager = MockTransportManager();
  final mockTransportConnection = MockTransportConnection();
  // Complex setup with many mocks...
});
```

### New Testing (Easy)
```dart
// New: Easy to test with clean interfaces
testWidgets('chat service test', (tester) async {
  // Simple mock transport
  final mockTransport = MockTransport();
  final chatService = ModernChatService(transport: mockTransport);
  
  // Clean, predictable testing
  await chatService.initialize();
  // Test behavior...
});
```

## Available Transport Implementations

### 1. TcpTransport
- **Use Case**: Local network communication over WiFi/Ethernet
- **Features**: Automatic peer discovery via network scanning
- **Configuration**: Port, bind address, display name

```dart
final transport = TcpTransport(
  port: 8080,
  displayName: 'My Node',
  bindAddress: InternetAddress.anyIPv4,
);
```

### 2. NearbyTransport  
- **Use Case**: Local device-to-device communication
- **Features**: Bluetooth + WiFi, no internet required
- **Configuration**: Node ID, display name, service ID, strategy

```dart
final transport = NearbyTransport(
  nodeId: 'user123',
  displayName: 'Alice',
  serviceId: 'com.myapp.service',
  strategy: Strategy.P2P_CLUSTER,
);
```

### 3. ChatNearbyTransport
- **Use Case**: Optimized for chat applications using Nearby Connections
- **Features**: Chat-specific error handling and logging
- **Configuration**: Same as NearbyTransport but with chat optimizations

```dart
final transport = ChatNearbyTransport(
  nodeId: userId,
  displayName: userName,
  serviceId: 'com.eventually.chat',
);
```

## Compatibility

### Backwards Compatibility
- Old interfaces are marked as `@Deprecated` but still functional
- Gradual migration is supported - you can migrate one component at a time
- Both old and new systems can coexist during transition

### Breaking Changes
- `TransportManager` → `Transport` interface change
- `TransportEndpoint` → `TransportPeer` with richer metadata
- `TransportConnection` → Direct `Transport` usage
- Event handling moved from callbacks to streams

## Example Applications

### Complete Chat App Migration
See `apps/eventually_chat/lib/services/modern_chat_service.dart` for a complete example of migrating a chat application to the new transport interface.

### Key Changes in Chat App:
1. **Service Initialization**: Cleaner dependency injection
2. **Peer Discovery**: Simplified peer management  
3. **Message Handling**: Stream-based reactive programming
4. **Error Handling**: Transport-specific exceptions
5. **Testing**: Much easier to mock and test

## Migration Checklist

- [ ] Replace `TransportManager` implementations with `Transport` implementations
- [ ] Update `TransportPeerManager` to `ModernTransportPeerManager`
- [ ] Change `TransportEndpoint` references to `TransportPeer`
- [ ] Replace callback-based message handling with stream-based handling
- [ ] Update service initialization to use dependency injection pattern
- [ ] Update tests to use new mock transport pattern
- [ ] Verify error handling uses new transport exceptions
- [ ] Test peer discovery and connection management
- [ ] Validate message sending and receiving functionality

## Getting Help

If you encounter issues during migration:

1. **Check Examples**: Look at `example/simple_transport_example.dart`
2. **Review Tests**: Transport tests show expected usage patterns  
3. **API Documentation**: All interfaces are fully documented
4. **Chat App**: Complete working example in `apps/eventually_chat/`

## Future Plans

The new transport interface enables several future improvements:

- **WebSocket Transport**: For web and server applications
- **HTTP Transport**: For request/response patterns  
- **Multicast Transport**: For efficient broadcast scenarios
- **Relay Transport**: For NAT traversal and internet routing
- **Hybrid Transport**: Automatically switch between multiple transports

The clean separation of concerns makes adding these new transports straightforward without changing application-layer code.