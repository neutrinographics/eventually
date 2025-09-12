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
  handshakeProtocol: JsonHandshakeProtocol(),
  approvalHandler: AutoApprovalHandler(),
);

final transport = TransportManager(config);

// Listen for discovered devices
transport.devicesDiscovered.listen((device) {
  print('Found device: ${device.displayName} at ${device.address.value}');
  // Connect to interesting devices
  transport.connectToDevice(device.address);
});

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

// Connect to a device (peer ID discovered via handshake)
final result = await transport.connectToDevice(DeviceAddress('device-addr'));
// Or connect to a known peer
// final result = await transport.connectToPeer(PeerId('known-peer'));

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

### Device Discovery vs Peer Management

The library separates device discovery from peer management:

**Device Discovery** (transport-level):
- Finds devices on the network with their addresses and display names
- No peer identity known yet (requires handshake)
- Example: Nearby Connections finds endpoint IDs, Bluetooth finds MAC addresses

**Peer Management** (application-level):
- Manages known peers with verified identities
- Created after successful connection and handshake
- Tracks peer status, metadata, and connection state

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
Low-level transport implementation (TCP, WebSocket, etc.)

```dart
abstract interface class TransportProtocol {
  Future<void> startListening();
  Future<void> stopListening();
  Future<TransportConnection?> connect(DeviceAddress address);
  Stream<IncomingConnectionAttempt> get incomingConnections;
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

### DeviceDiscovery
Mechanism for finding devices on the network (before peer identification)

```dart
abstract interface class DeviceDiscovery {
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Stream<DiscoveredDevice> get devicesDiscovered;
  Stream<DiscoveredDevice> get devicesLost;
}
```

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

To implement a custom transport (e.g., for nearby connections, custom UDP, etc.):

```dart
class MyTransportProtocol implements TransportProtocol {
  @override
  Future<void> startListening() async {
    // Start listening for connections
    // The address/port configuration is handled internally
  }

  @override
  Future<TransportConnection?> connect(DeviceAddress address) async {
    // Establish connection to the address
    // Return TransportConnection or null if failed
  }

  @override
  Stream<IncomingConnectionAttempt> get incomingConnections {
    // Return stream of incoming connection attempts
  }

  // ... implement other methods
}

class MyDeviceDiscovery implements DeviceDiscovery {
  @override
  Future<void> startDiscovery() async {
    // Start discovering devices (e.g., broadcast, mDNS, Bluetooth scan)
  }

  @override
  Stream<DiscoveredDevice> get devicesDiscovered {
    // Return stream of discovered devices with addresses and display names
  }

  // ... implement other methods
}

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
  localPeerId: PeerId('my-peer-id'),
  protocol: myProtocol,
  handshakeProtocol: myHandshake,
  approvalHandler: myApprovalHandler,
  deviceDiscovery: myDeviceDiscovery,   // Optional
  peerStore: myStore,                   // Optional
  connectionTimeout: Duration(seconds: 30),
  handshakeTimeout: Duration(seconds: 10),
  maxConnections: 100,
);
```

## Default Implementations

### JsonHandshakeProtocol
Simple JSON-based handshake for peer identification:

```dart
final handshake = JsonHandshakeProtocol(
  timeout: Duration(seconds: 10),
);
```

### InMemoryPeerStore
In-memory peer storage with live updates:

```dart
final store = InMemoryPeerStore();
```

### BroadcastDeviceDiscovery
Broadcast-based device discovery:

```dart
final discovery = BroadcastDeviceDiscovery(
  localDisplayName: 'My Device',
  broadcastInterval: Duration(seconds: 5),
  deviceTimeout: Duration(minutes: 2),
);
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