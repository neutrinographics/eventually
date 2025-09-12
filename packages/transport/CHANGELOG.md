# Changelog

All notable changes to the `transport` package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-01-XX

### Added
- Initial release of the transport library
- Core transport interfaces for pluggable protocols
- `TransportManager` for orchestrating peer connections and messaging
- Generic peer-to-peer connection management
- Distinction between device addresses and peer IDs
- Live updates for peer status changes and incoming messages
- Customizable handshake protocols with default JSON implementation
- Connection approval/rejection mechanisms with built-in handlers:
  - `AutoApprovalHandler` - automatically accepts connections
  - `RejectAllHandler` - rejects all connections
  - `ManualApprovalHandler` - custom approval logic via callbacks
- Peer discovery interface with broadcast-based default implementation
- Peer storage interface with in-memory default implementation
- Configurable connection limits and timeouts
- Comprehensive test suite with mock implementations
- Example TCP transport protocol implementation
- Complete documentation and usage examples

### Features
- **Transport Protocols**: Pluggable low-level transport implementations
- **Handshake Protocols**: Customizable peer identification during connection
- **Peer Discovery**: Automatic peer discovery with configurable mechanisms
- **Peer Storage**: Optional persistent storage for peer information
- **Connection Management**: Automatic handling of connection lifecycle
- **Message Passing**: Reliable message delivery between connected peers
- **Event Streams**: Real-time notifications for peer and connection events
- **Configuration**: Flexible configuration with sensible defaults

### Core Classes
- `TransportManager` - Main orchestration class
- `TransportConfig` - Configuration container
- `Peer` - Represents a network peer with status and metadata
- `TransportMessage` - Message container for peer-to-peer communication
- `PeerId` - Unique peer identifier
- `DeviceAddress` - Network address representation
- `JsonHandshakeProtocol` - Default JSON-based handshake implementation
- `InMemoryPeerStore` - Default in-memory peer storage
- `BroadcastPeerDiscovery` - Default broadcast-based peer discovery

### Examples
- Basic usage example with in-memory transport
- TCP transport protocol implementation
- Comprehensive documentation with code samples