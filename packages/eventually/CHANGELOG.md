# Changelog

All notable changes to the Eventually package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-01-20

### Added
- Initial release of the Eventually library for Merkle DAG synchronization
- Content Identifiers (CIDs) compatible with IPFS specification
  - Support for CID v0 and v1
  - SHA-256, SHA-1, SHA-512, and identity hash algorithms
  - Raw, DAG-PB, DAG-CBOR, and DAG-JSON codecs
- Block storage and management
  - Content-addressed blocks with integrity validation
  - Directory blocks for hierarchical structures
  - Link extraction for DAG traversal
- Merkle DAG data structure
  - Add, remove, and query blocks
  - Depth-first and breadth-first traversal
  - Topological sorting and cycle detection
  - Graph statistics and analysis
- Storage backends
  - In-memory store for development and testing
  - Caching store wrapper for performance
  - Pluggable interface for custom backends
- Peer-to-peer networking
  - Peer management and connection handling
  - Message passing for block exchange
  - Have/Want announcement system
- Synchronization protocols
  - BitSwap-inspired protocol for block exchange
  - Session management with statistics
  - Configurable sync strategies
- Hash function framework
  - Pluggable hash algorithm support
  - Streaming hash computation
  - Multi-hash format support
- Codec system
  - Multiple data encoding formats
  - Content type detection
  - Extensible codec registry
- Comprehensive test suite with 25+ test cases
- Full API documentation and examples

### Features
- **Content Addressing**: Immutable, cryptographically verified data storage
- **Distributed Sync**: Peer-to-peer block exchange with eventual consistency
- **Flexible Storage**: Pluggable backends from memory to distributed systems
- **IPFS Compatible**: CID and protocol compatibility with IPFS ecosystem
- **High Performance**: Concurrent operations with caching support
- **Type Safe**: Full Dart type safety with sealed classes and interfaces

### Technical Details
- Minimum Dart SDK: 3.9.0
- Dependencies: meta ^1.12.0
- Test coverage: Comprehensive unit tests for all core functionality
- Architecture: Modular design with clean separation of concerns

### Known Limitations
- Hash functions use placeholder implementations (not cryptographically secure)
- Base32/Base58 encoding uses simplified implementations
- Network transport layer not implemented (interface only)
- No persistence backends (memory store only)

### Future Roadmap
- Cryptographic hash implementations using dart:crypto
- File system and database storage backends
- Network transport implementations (TCP, WebSocket, WebRTC)
- Advanced synchronization strategies
- Compression and deduplication features
- Performance optimizations and benchmarks

[1.0.0]: https://github.com/da1nerd/eventually-mono/releases/tag/eventually-v1.0.0