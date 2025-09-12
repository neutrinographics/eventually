# Transport

A generic transport library for handling peer-to-peer network connections with customizable protocols and handshakes.

## Features

- **Generic Transport Interface**: Pluggable transport protocols (TCP, WebSocket, Bluetooth, etc.)
- **Device Discovery & Management**: Automatic device discovery with configurable mechanisms
- **Connection Management**: Automatic connection handling with approval/rejection workflows
- **Address vs Peer ID Distinction**: Separate device addresses from peer identities
- **Live Updates**: Real-time streams for device discovery, peer status changes and incoming messages
- **Customizable Handshakes**: Default JSON handshake with option to implement custom protocols
- **Persistent Peer Storage**: Optional peer information persistence
- **Connection Limits**: Configurable maximum concurrent connections
- **Auto/Manual Approval**: Flexible connection approval mechanisms

## Quick Start

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  transport: ^1.0.0
```

### Basic Usage

```dart
import 'package:transport/transport.dart';

// Create a transport manager
final config = TransportConfig(
  localPeerId: PeerId('my-peer-id'),
  protocol: MyTransportProtocol(), // Your transport implementation
  // handshakeProtocol: JsonHandshakeProtocol(), // Optional - this is the default
  // approvalHandler: AutoApprovalHandler(),     // Optional - this is the default
);

final transport = TransportManager(config);

// Application only sees peers - device discovery is handled internally
// Peers appear automatically when devices are discovered and connected

// Listen for peer updates and messages
transport.peerUpdates.listen((peer) {
  print('Peer ${peer.id.value} is now ${peer.status}');
});

transport.messagesReceived.listen((message) {
  final text = String.fromCharCodes(message.data);
  print('Received: $text from ${message.senderId.value}');
});

// Start the transport (starts listening and device discovery)
await transport.start();

// Connect to a known peer (if you have the peer ID)
final result = await transport.connectToPeer(PeerId('known-peer'));

if (result.result == ConnectionResult.success) {
  // Send a message
  final message = TransportMessage(
    senderId: config.localPeerId,
    recipientId: result.peerId,
    data: Uint8List.fromList('Hello!'.codeUnits),
    timestamp: DateTime.now(),
  );
  await transport.sendMessage(message);
}
```

## Core Concepts

### Device Address vs Peer ID

The library maintains a clear distinction between:
- **Device Address**: Where a device can be reached (IP:port, Bluetooth MAC, etc.)
- **Peer ID**: Unique identifier for the peer application running on that device

This allows the same peer to be reachable at different addresses over time.

### Transport vs Application Layer Separation

The library maintains clean separation between transport and application concerns:

**Transport Layer** (internal):
- Device discovery (finding devices on network)
- Connection establishment (connecting to discovered devices)
- Address management (device addresses, endpoint IDs)
- Handshake protocols (peer identification)

**Application Layer** (public API):
- Peer management (identified peers only)
- Message passing between peers
- Peer status monitoring
- Connection approval/rejection

Applications never see transport-level details like device addresses or discovery events.

### Peer Lifecycle

Peers go through the following states:
1. `connecting` - Connection attempt in progress
2. `connected` - Successfully connected and ready for messaging
3. `disconnecting` - Connection being closed
4. `disconnected` - No active connection
5. `failed` - Connection attempt failed

### Connection Approval

Three built-in approval mechanisms:
- `AutoApprovalHandler` - Automatically accepts all connections
- `RejectAllHandler` - Rejects all incoming connections
- `ManualApprovalHandler` - Uses a callback for custom logic

## Architecture

The transport library is built around several key interfaces:

### TransportProtocol
Low-level transport implementation (TCP, WebSocket, etc.) with built-in device discovery

```dart
abstract interface class TransportProtocol {
  // Connection management
  Future<void> startListening();
  Future<void> stopListening();
  Future<TransportConnection?> connect(DeviceAddress address);
  Stream<IncomingConnectionAttempt> get incomingConnections;
  bool get isListening;
  
  // Device discovery (integrated)
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Stream<DiscoveredDevice> get devicesDiscovered;
  Stream<DiscoveredDevice> get devicesLost;
  bool get isDiscovering;
}
```

### HandshakeProtocol
Handles peer identification during connection establishment

```dart
abstract interface class HandshakeProtocol {
  Future<HandshakeResult> initiateHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  );
  Future<HandshakeResult> respondToHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  );
}
```

### ~~DeviceDiscovery~~ (Deprecated)
Device discovery is now integrated into TransportProtocol. The separate DeviceDiscovery interface has been deprecated and will be removed in a future version.

Previously, device discovery was a separate component, but it's now part of the transport protocol implementation since different transport types (TCP, Bluetooth, WebSocket) require different discovery mechanisms.

### PeerStore
Persistent storage for peer information

```dart
abstract interface class PeerStore {
  Future<void> storePeer(Peer peer);
  Future<void> removePeer(PeerId peerId);
  Future<Peer?> getPeer(PeerId peerId);
  Future<List<Peer>> getAllPeers();
  Stream<PeerStoreEvent> get peerUpdates;
}
```

## Implementing Custom Transport Protocols

To implement a custom transport (e.g., for nearby connections, custom UDP, etc.), you now need to implement both connection management and device discovery:

```dart
class MyTransportProtocol implements TransportProtocol {
  // Connection management
  @override
  Future<void> startListening() async {
    // Start listening for connections
  }

  @override
  Future<TransportConnection?> connect(DeviceAddress address) async {
    // Establish connection to the address
    // Return TransportConnection or null if failed
  }
  
  @override
  Stream<IncomingConnectionAttempt> get incomingConnections {
    // Return stream of connection attempts
  }

  @override
  bool get isListening => _isListening;

  // Device discovery (integrated)
  @override
  Future<void> startDiscovery() async {
    // Start discovering devices (e.g., broadcast, mDNS, Bluetooth scan)
  }

  @override
  Stream<DiscoveredDevice> get devicesDiscovered {
    // Return stream of discovered devices with addresses and display names
  }

  @override
  Stream<DiscoveredDevice> get devicesLost {
    // Return stream of devices that are no longer available
  }

  @override
  bool get isDiscovering => _isDiscovering;
}

// Device discovery is now part of TransportProtocol - no separate implementation needed!

class MyTransportConnection implements TransportConnection {
  @override
  Future<void> send(Uint8List data) async {
    // Send raw bytes over the connection
  }

  @override
  Stream<Uint8List> get dataReceived {
    // Return stream of received raw bytes
  }

  // ... implement other methods
}
```

## Implementing Custom Handshakes

For custom handshake protocols (e.g., with authentication, capabilities exchange):

```dart
class CustomHandshakeProtocol implements HandshakeProtocol {
  @override
  Future<HandshakeResult> initiateHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  ) async {
    // Send handshake initiation
    // Wait for response
    // Return HandshakeResult with success/failure and remote peer ID
  }

  @override
  Future<HandshakeResult> respondToHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  ) async {
    // Wait for handshake initiation
    // Send response
    // Return HandshakeResult with success/failure and remote peer ID
  }
}
```

## Configuration Options

```dart
final config = TransportConfig(
  localPeerId: PeerId('test-peer'),
  protocol: myProtocol,                    // Includes device discovery
  handshakeProtocol: myHandshake,          // Optional - defaults to JsonHandshakeProtocol
  approvalHandler: myApprovalHandler,      // Optional - defaults to AutoApprovalHandler
  connectionPolicy: myConnectionPolicy,    // Optional - which devices to connect to
  peerStore: myStore,                      // Optional - peer persistence
  connectionTimeout: Duration(seconds: 30),
  handshakeTimeout: Duration(seconds: 10),
  maxConnections: 100,
);
```

## Default Implementations

### JsonHandshakeProtocol
Simple JSON-based handshake for peer identification (used by default):

```dart
final handshake = JsonHandshakeProtocol(
  timeout: Duration(seconds: 10),
);

// Or just use the default in TransportConfig:
final config = TransportConfig(
  localPeerId: PeerId('my-peer'),
  protocol: myProtocol,
  // handshakeProtocol automatically defaults to JsonHandshakeProtocol()
);
```

### InMemoryPeerStore
In-memory peer storage with live updates:

```dart
final store = InMemoryPeerStore();
```

### ~~BroadcastDeviceDiscovery~~ (Deprecated)
BroadcastDeviceDiscovery is still available for backward compatibility, but device discovery should now be implemented within your TransportProtocol. Different transport protocols will have different discovery mechanisms:

- **TCP/UDP**: mDNS, UPnP, or broadcast packets
- **Bluetooth**: Bluetooth device scanning
- **WebSocket**: Server-mediated discovery
- **Nearby Connections**: Platform-specific nearby discovery APIs

### Connection Policies
Control which discovered devices to automatically connect to:

```dart
// Auto-connect to all discovered devices
final policy = AutoConnectPolicy();

// Never auto-connect (manual peer connections only)
final policy = ManualConnectPolicy();

// Custom logic for connection decisions
final policy = PolicyBasedConnectionPolicy((device) async {
  return device.displayName.contains('MyApp');
});
```

## Examples

Check out the `/example` directory for complete working examples:
- `basic_example.dart` - In-memory transport demonstration
- TCP transport implementation in `/lib/src/examples/`

## Testing

Run the tests with:

```bash
dart test
```

The test suite includes comprehensive tests for all core functionality using mock implementations.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
