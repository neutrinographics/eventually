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
      final cidBytes = cid.bytes;
      // Add CID length as 4-byte big-endian integer, then CID bytes
      buffer.addAll([
        (cidBytes.length >> 24) & 0xFF,
        (cidBytes.length >> 16) & 0xFF,
        (cidBytes.length >> 8) & 0xFF,
        cidBytes.length & 0xFF,
      ]);
      buffer.addAll(cidBytes);
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
      final cidBytes = cid.bytes;
      // Add CID length as 4-byte big-endian integer, then CID bytes
      buffer.addAll([
        (cidBytes.length >> 24) & 0xFF,
        (cidBytes.length >> 16) & 0xFF,
        (cidBytes.length >> 8) & 0xFF,
        cidBytes.length & 0xFF,
      ]);
      buffer.addAll(cidBytes);
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
      // Find the first null byte to separate type from data
      int typeEnd = 0;
      while (typeEnd < bytes.length && bytes[typeEnd] != 0) {
        typeEnd++;
      }

      if (typeEnd == bytes.length) return null;

      final type = String.fromCharCodes(bytes.sublist(0, typeEnd));
      final dataBytes = bytes.sublist(typeEnd + 1);

      switch (type) {
        case 'have':
          return _decodeHave(dataBytes);
        case 'want':
          return _decodeWant(dataBytes);
        case 'block_request':
          return _decodeBlockRequest(dataBytes);
        case 'block_response':
          return _decodeBlockResponse(dataBytes);
        default:
          return null;
      }
    } catch (e) {
      return null;
    }
  }

  static Have? _decodeHave(Uint8List dataBytes) {
    if (dataBytes.isEmpty) return Have(cids: {});

    final cids = <CID>{};
    int offset = 0;

    while (offset + 4 < dataBytes.length) {
      // Read CID length as 4-byte big-endian integer
      final cidLength =
          (dataBytes[offset] << 24) |
          (dataBytes[offset + 1] << 16) |
          (dataBytes[offset + 2] << 8) |
          dataBytes[offset + 3];
      offset += 4;

      if (offset + cidLength > dataBytes.length) break;

      try {
        final cidBytes = dataBytes.sublist(offset, offset + cidLength);
        final cid = CID.fromBytes(cidBytes);
        cids.add(cid);
      } catch (e) {
        // Skip invalid CIDs
      }

      offset += cidLength;
    }

    return Have(cids: cids);
  }

  static Want? _decodeWant(Uint8List dataBytes) {
    if (dataBytes.isEmpty) return Want(cids: {});

    final cids = <CID>{};
    int offset = 0;

    while (offset + 4 < dataBytes.length) {
      // Read CID length as 4-byte big-endian integer
      final cidLength =
          (dataBytes[offset] << 24) |
          (dataBytes[offset + 1] << 16) |
          (dataBytes[offset + 2] << 8) |
          dataBytes[offset + 3];
      offset += 4;

      if (offset + cidLength > dataBytes.length) break;

      try {
        final cidBytes = dataBytes.sublist(offset, offset + cidLength);
        final cid = CID.fromBytes(cidBytes);
        cids.add(cid);
      } catch (e) {
        // Skip invalid CIDs
      }

      offset += cidLength;
    }

    return Want(cids: cids);
  }

  static BlockRequest? _decodeBlockRequest(Uint8List dataBytes) {
    if (dataBytes.isEmpty) return null;

    try {
      final cid = CID.fromBytes(dataBytes);
      return BlockRequest(cid: cid);
    } catch (e) {
      return null;
    }
  }

  static BlockResponse? _decodeBlockResponse(Uint8List dataBytes) {
    if (dataBytes.isEmpty) return null;

    try {
      // Find the first null separator between CID and block data
      int cidEnd = 0;
      while (cidEnd < dataBytes.length && dataBytes[cidEnd] != 0) {
        cidEnd++;
      }

      if (cidEnd >= dataBytes.length) return null;

      final cidBytes = dataBytes.sublist(0, cidEnd);
      final blockData = dataBytes.sublist(cidEnd + 1);

      final cid = CID.fromBytes(cidBytes);
      final block = Block.withCid(cid, blockData);

      return BlockResponse(block: block);
    } catch (e) {
      return null;
    }
  }
}
