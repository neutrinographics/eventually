# Eventually

A Dart library for Merkle DAG synchronization with IPFS-like protocols, supporting distributed content-addressed storage and peer-to-peer sync.

## Features

- **Content-Addressed Storage**: Store and retrieve data using cryptographic hashes (CIDs)
- **Merkle DAG**: Build directed acyclic graphs of content with automatic link discovery
- **Peer-to-Peer Sync**: Synchronize data between peers using BitSwap-inspired protocols
- **Multiple Storage Backends**: In-memory store with support for custom implementations
- **Flexible Codecs**: Support for raw data, DAG-PB, DAG-CBOR, and DAG-JSON formats
- **Hash Functions**: Pluggable hash function support (SHA-256, SHA-1, SHA-512, identity)

## Getting Started

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  eventually: ^1.0.0
```

## Basic Usage

### Creating and Storing Blocks

```dart
import 'package:eventually/eventually.dart';

// Create a block with raw data
final data = [1, 2, 3, 4, 5];
final block = Block.fromData(data, codec: Codec.raw);

// Set up a store
final store = MemoryStore();

// Store the block
await store.put(block);

// Retrieve by CID
final retrieved = await store.get(block.cid);
print('Retrieved block with ${retrieved?.size} bytes');
```

### Building a DAG

```dart
// Create a DAG
final dag = DAG();

// Add blocks to build the graph
dag.addBlock(block1);
dag.addBlock(block2);
dag.addBlock(block3);

// Traverse the DAG
dag.depthFirstTraversal(rootCid, (block) {
  print('Visiting block: ${block.cid}');
  return true; // Continue traversal
});

// Get statistics
final stats = dag.calculateStats();
print('DAG has ${stats.totalBlocks} blocks, ${stats.totalSize} bytes');
```

### Peer-to-Peer Synchronization

```dart
// Set up synchronization
final synchronizer = DefaultSynchronizer(
  store: store,
  dag: dag,
  peerManager: myPeerManager,
);

// Sync with a specific peer
final peer = Peer(id: 'peer-123', address: '127.0.0.1:8080');
final result = await synchronizer.syncWithPeer(peer);

print('Sync completed: received ${result.blocksReceived} blocks');

// Start continuous sync
synchronizer.startContinuousSync(
  interval: Duration(seconds: 30),
);
```

## Core Concepts

### Content Identifiers (CIDs)

CIDs are self-describing content addresses that uniquely identify data:

```dart
// Create a CID v1 with SHA-256
final multihash = Multihash.fromDigest(HashCode.sha256, hashBytes);
final cid = CID.v1(codec: Codec.raw, multihash: multihash);

// Parse from string
final parsed = CID.parse('bafkreieuiak...');

// CID v0 (legacy IPFS format)
final cidV0 = CID.v0(sha256Multihash);
```

### Blocks and Data Storage

Blocks are the fundamental units of storage:

```dart
// Create from data (CID computed automatically)
final block = Block.fromData(myData, codec: Codec.dagCbor);

// Create with known CID
final block = Block.withCid(knownCid, myData);

// Validate integrity
if (block.validate()) {
  print('Block is valid');
}

// Extract links to other blocks
final links = block.extractLinks();
```

### Directory Structures

Create directory-like structures with named entries:

```dart
final entries = {
  'file1.txt': DirectoryEntry.file(fileCid, fileSize),
  'subdir': DirectoryEntry.directory(subdirCid, subdirSize),
};

final dirBlock = DirectoryBlock(entries);

// Access entries
if (dirBlock.contains('file1.txt')) {
  final entry = dirBlock['file1.txt'];
  print('File size: ${entry?.size}');
}
```

## Protocols

### BitSwap Protocol

The library includes a BitSwap-inspired protocol for efficient block exchange:

```dart
final protocol = BitSwapProtocol();

// Start a sync session
final session = await protocol.startSync(connection, rootCids);

// Request specific blocks
await session.requestBlocks({cid1, cid2, cid3});

// Send blocks to peer
await session.sendBlocks({block1, block2});

// Monitor session events
session.events.listen((event) {
  if (event is BlocksReceived) {
    print('Received ${event.blocks.length} blocks');
  }
});
```

## Storage Backends

### Memory Store

For development and testing:

```dart
final store = MemoryStore();

// Optional caching wrapper
final cachedStore = CachedStore(store, maxCacheSize: 1000);
```

### Custom Store Implementation

Implement the `Store` interface for custom backends:

```dart
class MyCustomStore implements Store {
  @override
  Future<bool> put(Block block) async {
    // Your storage logic here
  }
  
  @override
  Future<Block?> get(CID cid) async {
    // Your retrieval logic here
  }
  
  // ... implement other methods
}
```

## Hash Functions and Codecs

### Supported Hash Functions

- Identity (for small data)
- SHA-256 (recommended)
- SHA-1 (legacy support)
- SHA-512

```dart
// Create custom hasher
final hasher = HashFactory.create(HashCode.sha256);
final digest = hasher.hash(myData);

// Streaming hash computation
final streamingHasher = hasher.createStreaming();
streamingHasher.update(chunk1);
streamingHasher.update(chunk2);
final finalHash = streamingHasher.finish();
```

### Supported Codecs

- Raw (opaque bytes)
- DAG-PB (IPFS-style protobuf)
- DAG-CBOR (structured data with CID links)
- DAG-JSON (JSON with CID links)

```dart
// Create codec
final codec = CodecFactory.create(Codec.dagCbor);

// Encode structured data
final encoded = codec.encode(myStructuredData);

// Detect codec from data
final detectedCodec = CodecFactory.detectCodec(someBytes);
```

## Error Handling

The library provides specific exception types:

```dart
try {
  final block = await store.get(cid);
} catch (e) {
  if (e is BlockNotFoundException) {
    print('Block ${e.cid} not found');
  } else if (e is StoreException) {
    print('Store error: ${e.message}');
  }
}
```

## Performance Considerations

- Use caching stores for frequently accessed data
- Implement garbage collection to remove unreferenced blocks
- Consider snapshot strategies for large DAGs
- Batch operations when possible

```dart
// Garbage collection
final roots = {rootCid1, rootCid2};
final gcResult = await store.collectGarbage(roots);
print('Freed ${gcResult.bytesFreed} bytes in ${gcResult.duration}');
```

## Contributing

Contributions are welcome! Please see our contributing guidelines and submit pull requests to our repository.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Related Projects

- [IPFS](https://ipfs.io/) - The InterPlanetary File System
- [libp2p](https://libp2p.io/) - Modular network stack for peer-to-peer applications
- [Multiformats](https://multiformats.io/) - Self-describing format specifications

## Acknowledgments

This library is inspired by IPFS and implements similar concepts for Dart applications. Special thanks to the IPFS community for pioneering content-addressed storage systems.