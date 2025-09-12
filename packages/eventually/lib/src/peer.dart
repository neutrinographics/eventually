import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'cid.dart';
import 'block.dart';

/// Base class for sync messages exchanged between peers.
@immutable
sealed class SyncMessage {
  /// Creates a message with the given type and timestamp.
  SyncMessage({required this.type, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// The type of message.
  final String type;

  /// When this message was created.
  final DateTime timestamp;

  /// Converts the message to bytes for transmission.
  Uint8List toBytes();
}

/// Message requesting a block from a peer.
@immutable
final class BlockRequest extends SyncMessage {
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
final class BlockResponse extends SyncMessage {
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
final class Have extends SyncMessage {
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
final class Want extends SyncMessage {
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

/// Utility class for encoding/decoding sync messages.
class SyncMessageCodec {
  /// Decodes a sync message from bytes.
  static SyncMessage? decode(Uint8List bytes) {
    if (bytes.isEmpty) return null;

    try {
      // Simple decoding based on message type
      final string = String.fromCharCodes(bytes);
      final parts = string.split('\x00');

      if (parts.isEmpty) return null;

      final type = parts[0];

      switch (type) {
        case 'have':
          return _decodeHave(parts);
        case 'want':
          return _decodeWant(parts);
        case 'block_request':
          return _decodeBlockRequest(parts);
        case 'block_response':
          return _decodeBlockResponse(parts);
        default:
          return null;
      }
    } catch (e) {
      return null;
    }
  }

  static Have? _decodeHave(List<String> parts) {
    if (parts.length < 2) return null;

    final cids = <CID>{};
    for (int i = 1; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        try {
          cids.add(CID.parse(parts[i]));
        } catch (e) {
          // Skip invalid CIDs
        }
      }
    }

    return Have(cids: cids);
  }

  static Want? _decodeWant(List<String> parts) {
    if (parts.length < 2) return null;

    final cids = <CID>{};
    for (int i = 1; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        try {
          cids.add(CID.parse(parts[i]));
        } catch (e) {
          // Skip invalid CIDs
        }
      }
    }

    return Want(cids: cids);
  }

  static BlockRequest? _decodeBlockRequest(List<String> parts) {
    if (parts.length < 2) return null;

    try {
      final cid = CID.parse(parts[1]);
      return BlockRequest(cid: cid);
    } catch (e) {
      return null;
    }
  }

  static BlockResponse? _decodeBlockResponse(List<String> parts) {
    // This would need more sophisticated parsing for the block data
    // For now, return null
    return null;
  }
}
