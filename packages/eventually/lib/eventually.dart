/// A Dart library for Merkle DAG synchronization with IPFS-like protocols.
///
/// This library provides the core building blocks for implementing distributed
/// content-addressed storage systems with support for Merkle DAGs, peer-to-peer
/// synchronization, and eventual consistency.
library eventually;

export 'src/cid.dart';
export 'src/block.dart';
export 'src/dag.dart';
export 'src/store.dart' hide BlockNotFoundException;
export 'src/sync.dart';
export 'src/peer.dart';
export 'src/peer_config.dart';
export 'src/transport.dart';
export 'src/transport_peer_manager.dart';
export 'src/peer_handshake.dart' hide TransportPeerConnection;
export 'src/protocol.dart';
export 'src/hash.dart';
export 'src/codec.dart' hide Codec;
