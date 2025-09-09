import 'dart:async';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'cid.dart';
import 'block.dart';

/// Represents a peer in the distributed network.
///
/// Peers can communicate with each other to synchronize content and
/// exchange blocks in the Merkle DAG system.
@immutable
class Peer {
  /// Creates a peer with the given identifier and address.
  const Peer({
    required this.id,
    required this.address,
    this.metadata = const {},
  });

  /// Unique identifier for this peer.
  final String id;

  /// Network address of the peer (e.g., IP:port, multiaddr).
  final String address;

  /// Additional metadata about the peer.
  final Map<String, dynamic> metadata;

  /// Creates a copy of this peer with updated properties.
  Peer copyWith({String? id, String? address, Map<String, dynamic>? metadata}) {
    return Peer(
      id: id ?? this.id,
      address: address ?? this.address,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Peer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          address == other.address &&
          metadata == other.metadata;

  @override
  int get hashCode => Object.hash(id, address, metadata);

  @override
  String toString() => 'Peer(id: $id, address: $address)';
}

/// Interface for peer-to-peer communication.
///
/// This provides the foundation for exchanging messages, blocks, and
/// synchronization information between peers in the network.
abstract interface class PeerConnection {
  /// The peer this connection is established with.
  Peer get peer;

  /// Whether this connection is currently active.
  bool get isConnected;

  /// Stream of incoming messages from the peer.
  Stream<Message> get messages;

  /// Connects to the peer.
  Future<void> connect();

  /// Disconnects from the peer.
  Future<void> disconnect();

  /// Sends a message to the peer.
  Future<void> sendMessage(dynamic message);

  /// Requests a block from the peer.
  Future<Block?> requestBlock(CID cid);

  /// Requests multiple blocks from the peer.
  Future<List<Block>> requestBlocks(List<CID> cids);

  /// Sends a block to the peer.
  Future<void> sendBlock(Block block);

  /// Checks if the peer has a specific block.
  Future<bool> hasBlock(CID cid);

  /// Gets the peer's advertised capabilities.
  Future<Set<String>> getCapabilities();

  /// Performs a ping to check connectivity and measure latency.
  Future<Duration> ping();
}

/// Base class for messages exchanged between peers.
@immutable
sealed class Message {
  /// Creates a message with the given type and timestamp.
  Message({required this.type, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// The type of message.
  final String type;

  /// When this message was created.
  final DateTime timestamp;

  /// Converts the message to bytes for transmission.
  Uint8List toBytes();

  /// Creates a message from bytes received over the network.
  static Message fromBytes(Uint8List bytes) {
    throw UnimplementedError('Message.fromBytes must be implemented');
  }
}

/// Message requesting a block from a peer.
@immutable
final class BlockRequest extends Message {
  /// Creates a block request message.
  BlockRequest({required this.cid, DateTime? timestamp})
    : super(type: 'block_request', timestamp: timestamp);

  /// The CID of the requested block.
  final CID cid;

  @override
  Uint8List toBytes() {
    // Simple encoding: type + cid bytes
    final typeBytes = type.codeUnits;
    final cidBytes = cid.bytes;

    return Uint8List.fromList([
      ...typeBytes,
      0x00, // separator
      ...cidBytes,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockRequest &&
          runtimeType == other.runtimeType &&
          cid == other.cid;

  @override
  int get hashCode => cid.hashCode;
}

/// Message containing a block in response to a request.
@immutable
final class BlockResponse extends Message {
  /// Creates a block response message.
  BlockResponse({required this.block, DateTime? timestamp})
    : super(type: 'block_response', timestamp: timestamp);

  /// The block being sent.
  final Block block;

  @override
  Uint8List toBytes() {
    final typeBytes = type.codeUnits;
    final cidBytes = block.cid.bytes;
    final blockData = block.data;

    return Uint8List.fromList([
      ...typeBytes,
      0x00, // separator
      ...cidBytes,
      0x00, // separator
      ...blockData,
    ]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockResponse &&
          runtimeType == other.runtimeType &&
          block == other.block;

  @override
  int get hashCode => block.hashCode;
}

/// Message advertising blocks that a peer has available.
@immutable
final class Have extends Message {
  /// Creates a have message.
  Have({required this.cids, DateTime? timestamp})
    : super(type: 'have', timestamp: timestamp);

  /// The CIDs that this peer has available.
  final Set<CID> cids;

  @override
  Uint8List toBytes() {
    final typeBytes = type.codeUnits;
    final buffer = <int>[...typeBytes, 0x00];

    for (final cid in cids) {
      buffer.addAll(cid.bytes);
      buffer.add(0x00); // separator
    }

    return Uint8List.fromList(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Have && runtimeType == other.runtimeType && cids == other.cids;

  @override
  int get hashCode => Object.hashAll(cids);
}

/// Message requesting information about what blocks a peer wants.
@immutable
final class Want extends Message {
  /// Creates a want message.
  Want({required this.cids, DateTime? timestamp})
    : super(type: 'want', timestamp: timestamp);

  /// The CIDs that this peer wants.
  final Set<CID> cids;

  @override
  Uint8List toBytes() {
    final typeBytes = type.codeUnits;
    final buffer = <int>[...typeBytes, 0x00];

    for (final cid in cids) {
      buffer.addAll(cid.bytes);
      buffer.add(0x00); // separator
    }

    return Uint8List.fromList(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Want && runtimeType == other.runtimeType && cids == other.cids;

  @override
  int get hashCode => Object.hashAll(cids);
}

/// Message for ping/pong to check connectivity.
@immutable
final class Ping extends Message {
  /// Creates a ping message.
  Ping({DateTime? timestamp}) : super(type: 'ping', timestamp: timestamp);

  @override
  Uint8List toBytes() {
    return Uint8List.fromList(type.codeUnits);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ping && runtimeType == other.runtimeType;

  @override
  int get hashCode => type.hashCode;
}

/// Message responding to a ping.
@immutable
final class Pong extends Message {
  /// Creates a pong message.
  Pong({DateTime? timestamp}) : super(type: 'pong', timestamp: timestamp);

  @override
  Uint8List toBytes() {
    return Uint8List.fromList(type.codeUnits);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Pong && runtimeType == other.runtimeType;

  @override
  int get hashCode => type.hashCode;
}

/// Manages connections to multiple peers.
abstract interface class PeerManager {
  /// All currently connected peers.
  Iterable<Peer> get connectedPeers;

  /// Stream of peer connection events.
  Stream<PeerEvent> get peerEvents;

  /// Connects to a peer.
  Future<PeerConnection> connect(Peer peer);

  /// Disconnects from a peer.
  Future<void> disconnect(String peerId);

  /// Disconnects from all peers.
  Future<void> disconnectAll();

  /// Finds peers that might have a specific block.
  Future<List<Peer>> findPeersWithBlock(CID cid);

  /// Broadcasts a message to all connected peers.
  Future<void> broadcast(Message message);

  /// Adds a peer to the known peers list.
  void addPeer(Peer peer);

  /// Removes a peer from the known peers list.
  void removePeer(String peerId);

  /// Gets a peer by ID.
  Peer? getPeer(String peerId);

  /// Gets statistics about peer connections.
  Future<PeerStats> getStats();
}

/// Events related to peer connections.
@immutable
sealed class PeerEvent {
  const PeerEvent({required this.peer, required this.timestamp});

  final Peer peer;
  final DateTime timestamp;
}

/// Event when a peer connects.
@immutable
final class PeerConnected extends PeerEvent {
  const PeerConnected({required super.peer, required super.timestamp});
}

/// Event when a peer disconnects.
@immutable
final class PeerDisconnected extends PeerEvent {
  const PeerDisconnected({
    required super.peer,
    required super.timestamp,
    this.reason,
  });

  final String? reason;
}

/// Event when a message is received from a peer.
@immutable
final class MessageReceived extends PeerEvent {
  const MessageReceived({
    required super.peer,
    required super.timestamp,
    required this.message,
  });

  final Message message;
}

/// Statistics about peer connections.
@immutable
class PeerStats {
  const PeerStats({
    required this.totalPeers,
    required this.connectedPeers,
    required this.totalMessages,
    required this.totalBytesReceived,
    required this.totalBytesSent,
    this.details = const {},
  });

  final int totalPeers;
  final int connectedPeers;
  final int totalMessages;
  final int totalBytesReceived;
  final int totalBytesSent;
  final Map<String, dynamic> details;

  @override
  String toString() =>
      'PeerStats('
      'total: $totalPeers, '
      'connected: $connectedPeers, '
      'messages: $totalMessages, '
      'bytes: ${totalBytesReceived + totalBytesSent}'
      ')';
}

/// Exception thrown when peer operations fail.
class PeerException implements Exception {
  const PeerException(this.message, {this.peer, this.cause});

  final String message;
  final Peer? peer;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('PeerException: $message');
    if (peer != null) {
      buffer.write(' (peer: ${peer!.id})');
    }
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}

/// Exception thrown when connection to a peer fails.
class ConnectionException extends PeerException {
  const ConnectionException(String message, {super.peer, super.cause})
    : super(message);
}

/// Exception thrown when a peer times out.
class PeerTimeoutException extends PeerException {
  const PeerTimeoutException(String message, {super.peer}) : super(message);
}
