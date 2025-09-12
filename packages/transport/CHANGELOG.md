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
- Live updates for device discovery, peer status changes and incoming messages
- Customizable handshake protocols with default JSON implementation
- Connection approval/rejection mechanisms with built-in handlers:
  - `AutoApprovalHandler` - automatically accepts connections
  - `RejectAllHandler` - rejects all connections
  - `ManualApprovalHandler` - custom approval logic via callbacks
- Device discovery interface with broadcast-based default implementation
- Peer storage interface with in-memory default implementation
- Configurable connection limits and timeouts
- Comprehensive test suite with mock implementations
- Example TCP transport protocol implementation
- Complete documentation and usage examples

### Breaking Changes
- **BREAKING**: Replaced `PeerDiscovery` with `DeviceDiscovery` interface
  - `DeviceDiscovery` finds devices before peer identification (more realistic for protocols like Nearby Connections)
  - `PeerDiscovery.peersDiscovered` → `DeviceDiscovery.devicesDiscovered` 
  - Peer objects are now only created after successful handshake
- **BREAKING**: `TransportManager.start()` simplified - no address parameter needed
- **BREAKING**: `TransportMessage` simplified - removed optional `messageId` field
- **BREAKING**: Updated `TransportConfig` to use `deviceDiscovery` instead of `peerDiscovery`

### Design Decisions
- Device discovery and peer management are now separate concerns:
  - **Device Discovery**: Transport-level finding of devices/endpoints (before peer identification)
  - **Peer Management**: Application-level management of identified peers (after handshake)
- `connectToDevice(DeviceAddress)` - Connect to discovered device, peer ID learned via handshake
- `connectToPeer(PeerId)` - Connect to known peer (requires address from peer store)
- Transport protocols handle their own listening address configuration
- Applications can include message IDs in payload if needed

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
- `BroadcastDeviceDiscovery` - Default broadcast-based device discovery
- `NoOpDeviceDiscovery` - No-op device discovery implementation

### Examples
- Basic usage example with in-memory transport
- TCP transport protocol implementation
- Comprehensive documentation with code samples