# Eventually

A Dart monorepo for Merkle DAG synchronization with IPFS-like protocols, supporting distributed content-addressed storage and peer-to-peer sync.

## Overview

Eventually is a collection of Dart packages that implement content-addressed storage, Merkle DAG structures, and peer-to-peer synchronization protocols. It provides the building blocks for creating distributed systems with eventual consistency, inspired by IPFS and similar technologies.

## Architecture

This monorepo contains packages that work together to provide:

- **Content-Addressed Storage**: Store and retrieve data using cryptographic hashes (CIDs)
- **Merkle DAG**: Build directed acyclic graphs of content with automatic link discovery
- **Peer-to-Peer Sync**: Exchange data between peers using BitSwap-inspired protocols
- **Multiple Storage Backends**: Pluggable storage systems for different use cases
- **Flexible Codecs**: Support for various data encoding formats

## Packages

### Core Package

- **[eventually](packages/eventually/)** - The main library containing all core functionality

### Future Packages (Planned)

- **eventually_storage** - Additional storage backends (file system, database, etc.)
- **eventually_network** - Network transport implementations
- **eventually_crypto** - Cryptographic primitives and utilities

## Getting Started

### Prerequisites

- Dart SDK 3.9.0 or later
- Melos for monorepo management

### Installation

1. Clone the repository:
```bash
git clone https://github.com/da1nerd/eventually-mono.git
cd eventually-mono
```

2. Install dependencies:
```bash
dart pub global activate melos
melos get-all
```

3. Run tests:
```bash
melos run test
```

### Basic Usage

Add the eventually package to your project:

```yaml
dependencies:
  eventually: ^1.0.0
```

Create and store content-addressed blocks:

```dart
import 'package:eventually/eventually.dart';

// Create a block with raw data
final data = [1, 2, 3, 4, 5];
final block = Block.fromData(data, codec: Codec.raw);

// Set up a store
final store = MemoryStore();
await store.put(block);

// Build a DAG
final dag = DAG();
dag.addBlock(block);

// Synchronize with peers
final synchronizer = DefaultSynchronizer(
  store: store,
  dag: dag,
  peerManager: myPeerManager,
);
```

## Development

### Project Structure

```
eventually/
├── packages/
│   └── eventually/          # Core library
│       ├── lib/
│       │   ├── src/
│       │   │   ├── cid.dart        # Content Identifiers
│       │   │   ├── block.dart      # Block storage
│       │   │   ├── dag.dart        # Merkle DAG
│       │   │   ├── store.dart      # Storage interface
│       │   │   ├── sync.dart       # Synchronization
│       │   │   ├── peer.dart       # P2P communication
│       │   │   ├── protocol.dart   # Sync protocols
│       │   │   ├── hash.dart       # Hash functions
│       │   │   └── codec.dart      # Data codecs
│       │   └── eventually.dart
│       ├── test/
│       └── pubspec.yaml
├── pubspec.yaml             # Workspace configuration
└── melos.yaml              # Melos configuration
```

### Available Scripts

Use Melos to run common development tasks:

```bash
# Run tests for all packages
melos run test

# Run static analysis
melos run analyze

# Format code
melos run format

# Version management
melos run version-patch      # Bump patch version
melos run version-minor      # Bump minor version
melos run version-major      # Bump major version

# Publishing
melos run publish-dry-run    # Preview what would be published
melos run publish-packages   # Publish to pub.dev

# Maintenance
melos run clean             # Clean build artifacts
melos run outdated          # Check for outdated dependencies
```

### Testing

Run all tests:

```bash
melos run test
```

Run tests for a specific package:

```bash
cd packages/eventually
dart test
```

### Code Style

This project follows Dart's recommended style guide. Use the linter configuration in `pubspec.yaml` and run:

```bash
melos run format
melos run analyze
```

## Key Features

### Content Identifiers (CIDs)

Self-describing content addresses compatible with IPFS:

```dart
// Create CID v1 with SHA-256
final cid = CID.v1(codec: Codec.raw, multihash: multihash);

// Parse from string
final parsed = CID.parse('bafkreieuiak...');
```

### Merkle DAG

Build graphs of content-addressed blocks:

```dart
final dag = DAG();
dag.addBlock(block);

// Traverse the DAG
dag.depthFirstTraversal(rootCid, (block) {
  print('Visiting: ${block.cid}');
  return true;
});
```

### Peer-to-Peer Sync

Exchange blocks between peers:

```dart
final protocol = BitSwapProtocol();
final session = await protocol.startSync(connection, rootCids);
await session.requestBlocks(missingCids);
```

## Use Cases

Eventually is suitable for building:

- **Distributed File Systems**: Content-addressed storage with deduplication
- **Version Control Systems**: Git-like versioning with Merkle trees
- **Distributed Databases**: Eventually consistent data stores
- **P2P Applications**: Decentralized content sharing
- **Backup Systems**: Incremental backups with content addressing

## Performance

The library is designed for performance and scalability:

- **Memory Efficient**: Uses streaming for large data sets
- **Concurrent**: Parallel block processing and network operations
- **Caching**: Optional caching layers for frequently accessed data
- **Garbage Collection**: Remove unreferenced blocks automatically

## Roadmap

- [ ] File system storage backend
- [ ] Database storage backends (SQLite, PostgreSQL)
- [ ] Network transport implementations (TCP, WebSocket, WebRTC)
- [ ] Advanced cryptographic features
- [ ] Compression support
- [ ] Web platform support

## Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Run the test suite and linter
5. Submit a pull request

### Development Setup

```bash
# Clone and setup
git clone https://github.com/da1nerd/eventually-mono.git
cd eventually-mono
melos get-all

# Run pre-commit checks
melos run analyze
melos run test
melos run format
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [IPFS](https://ipfs.io/) and the content-addressed web
- Uses concepts from [Merkle trees](https://en.wikipedia.org/wiki/Merkle_tree) and [DAGs](https://en.wikipedia.org/wiki/Directed_acyclic_graph)
- Protocol design influenced by [BitSwap](https://docs.ipfs.io/concepts/bitswap/) and [libp2p](https://libp2p.io/)

## Support

- [Documentation](https://github.com/da1nerd/eventually-mono/tree/main/packages/eventually)
- [Issues](https://github.com/da1nerd/eventually-mono/issues)
- [Discussions](https://github.com/da1nerd/eventually-mono/discussions)

---

**Eventually** - Building the content-addressed future, one block at a time.