/// A Dart library for Merkle DAG synchronization with IPFS-like protocols.
///
/// This library provides the core building blocks for implementing distributed
/// content-addressed storage systems with support for Merkle DAGs and content
/// synchronization.
///
/// Network transport and peer management are handled by the separate `transport`
/// package, allowing for clean separation between network and content concerns.
library eventually;

export 'src/cid.dart';
export 'src/block.dart';
export 'src/dag.dart';
export 'src/store.dart';
export 'src/sync.dart';
export 'src/peer.dart'; // Just sync message types
export 'src/protocol.dart';
export 'src/hash.dart';
export 'src/codec.dart';
