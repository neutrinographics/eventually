# Eventually Library Architecture: Separated Transport and Application Layers

## Overview

The Eventually library has been redesigned to properly separate transport-layer concerns from application-layer concerns. This separation follows networking best practices and allows for better modularity, testability, and flexibility in peer-to-peer systems.

## Architecture Layers

### 1. Transport Layer

The transport layer handles the physical/logical connections between endpoints without knowing anything about peer identities.

#### Key Components

- **`TransportEndpoint`**: Represents a transport address (e.g., IP:port, Bluetooth MAC, WebSocket URL)
- **`TransportConnection`**: Manages raw data communication over a transport protocol
- **`TransportManager`**: Discovers and manages transport connections

#### Responsibilities

- Network discovery (finding available endpoints)
- Connection establishment (TCP, UDP, WebSocket, Bluetooth, etc.)
- Raw data transmission
- Connection lifecycle management
- Transport-specific error handling

#### Example Transport Endpoints

```dart
// TCP endpoint
TransportEndpoint(
  address: '192.168.1.100:8080',
  protocol: 'tcp',
  metadata: {'encryption': 'tls'},
)

// Bluetooth endpoint
TransportEndpoint(
  address: 'AA:BB:CC:DD:EE:FF',
  protocol: 'bluetooth',
  metadata: {'service_uuid': '550e8400-e29b-41d4-a716-446655440000'},
)

// WebSocket endpoint
TransportEndpoint(
  address: 'ws://peer.example.com:9001/p2p',
  protocol: 'websocket',
  metadata: {'origin': 'https://myapp.com'},
)
```

### 2. Application Layer

The application layer handles peer identity and high-level communication after transport connections are established.

#### Key Components

- **`Peer`**: Represents a peer's application-layer identity (discovered after connection)
- **`PeerConnection`**: Provides application-layer communication interface
- **`PeerManager`**: Manages peer relationships and application-layer operations
- **`PeerHandshake`**: Negotiates peer identity over transport connections

#### Responsibilities

- Peer identity discovery through handshake protocols
- Application-level message routing
- Content synchronization
- High-level peer operations (block exchange, DAG sync)
- Peer capability negotiation

## Connection Flow

The new architecture follows this connection flow:

```
1. Transport Discovery
   └── TransportManager discovers endpoints (by address)

2. Transport Connection
   └── Establish raw connection to endpoint

3. Peer Handshake
   ├── Exchange peer identities
   ├── Negotiate capabilities
   └── Establish application-layer context

4. Application Communication
   └── Use logical peer IDs for high-level operations
```

### Step-by-Step Example

```dart
// 1. Start transport discovery
await transportManager.startDiscovery();

// 2. Get discovered endpoints
final endpoints = transportManager.connectedEndpoints;
// endpoints contain addresses like "192.168.1.100:8080"

// 3. Connect to endpoint (triggers handshake)
final peerConnection = await peerManager.connectToEndpoint(
  endpoints.first.address,
);

// 4. Now we know the peer's identity
final peer = peerConnection.peer; // Has ID like "alice-peer-123"

// 5. Use application-layer communication
await peerConnection.sendMessage(chatMessage);
final hasBlock = await peerConnection.hasBlock(cid);
```

## Key Benefits

### 1. Separation of Concerns

- **Transport layer**: Focuses on "how to connect"
- **Application layer**: Focuses on "who we're talking to and what we're saying"

### 2. Protocol Flexibility

- Support multiple transport protocols simultaneously
- Easy to add new transport mechanisms
- Transport-agnostic application code

### 3. Identity Security

- Peer identity is discovered through secure handshake
- Transport addresses can be ephemeral or dynamic
- Application logic works with stable peer IDs

### 4. Better Testing

- Mock transport layers for testing
- Separate testing of connection vs. application logic
- More focused unit tests

### 5. Network Adaptability

- Peers can change transport addresses
- Multiple transport connections to same peer
- Automatic failover between transports

## Migration from Old Architecture

### Before (Coupled)

```dart
// Old: Peer contained both transport and identity
final peer = Peer(
  id: 'alice-123',           // Application layer
  address: '192.168.1.100',  // Transport layer - mixed concerns!
);

await peerManager.connect(peer); // Had to know both ID and address
```

### After (Separated)

```dart
// New: Separate discovery and connection
final endpoints = await transportManager.discoverEndpoints();
final connection = await peerManager.connectToEndpoint(endpoints.first.address);

// Identity discovered during handshake
final peer = connection.peer; // ID learned after connection
```

## Implementation Details

### Handshake Protocol

The peer handshake uses a simple JSON-based protocol:

```json
// Handshake Request
{
  "type": "request",
  "peer_id": "alice-peer-123",
  "metadata": {
    "name": "Alice",
    "capabilities": ["blocks", "sync"],
    "version": "1.0.0"
  }
}

// Handshake Response
{
  "type": "response", 
  "peer_id": "bob-peer-456",
  "metadata": {
    "name": "Bob",
    "capabilities": ["blocks", "sync", "chat"],
    "version": "1.1.0"
  }
}
```

### Error Handling

The architecture provides distinct error types for each layer:

- **`TransportException`**: Network-level failures
- **`PeerHandshakeException`**: Identity negotiation failures  
- **`PeerException`**: Application-level communication failures

### Event System

Events are emitted at appropriate layers:

```dart
// Transport events
TransportEvent {
  EndpointDiscovered,
  TransportConnected,
  TransportDisconnected
}

// Application events  
PeerEvent {
  PeerDiscovered,
  PeerConnected,
  PeerDisconnected,
  MessageReceived
}
```

## Future Extensions

This architecture enables future enhancements:

1. **Multi-transport peers**: Single peer accessible via multiple transports
2. **Transport priorities**: Prefer certain transports (WiFi > cellular)
3. **Connection pooling**: Reuse transport connections for multiple peers
4. **Relay support**: Connect through intermediary peers
5. **Transport encryption**: Add encryption at transport layer
6. **Dynamic discovery**: Peer identity updates without reconnection

## Example Implementations

See the following files for complete implementations:

- `lib/src/transport_endpoint.dart` - Transport layer abstractions
- `lib/src/peer_handshake.dart` - Handshake protocol implementation
- `lib/src/peer.dart` - Updated application-layer peer abstractions
- `apps/eventually_chat/lib/services/mock_peer_manager.dart` - Reference implementation
- `example/separated_layers_example.dart` - Complete working example

This architecture provides a solid foundation for building robust, scalable peer-to-peer applications with clear separation between transport and application concerns.