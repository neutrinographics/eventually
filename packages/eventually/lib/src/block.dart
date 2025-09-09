import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'cid.dart';

/// A block represents a unit of data storage in the content-addressed system.
///
/// Blocks contain raw data and are identified by their CID (Content Identifier).
/// They form the foundation of the Merkle DAG structure, where each block
/// can reference other blocks through their CIDs.
@immutable
class Block {
  /// Creates a block with the given CID and data.
  const Block._({required this.cid, required this.data});

  /// The Content Identifier for this block.
  final CID cid;

  /// The raw data contained in this block.
  final Uint8List data;

  /// Creates a block from raw data using the specified codec and hash function.
  ///
  /// The CID is computed from the data using the provided parameters.
  factory Block.fromData(
    Uint8List data, {
    int codec = MultiCodec.raw,
    int hashCode = MultiHashCode.sha256,
  }) {
    final hash = _computeHash(data, hashCode);
    final multihash = Multihash.fromDigest(hashCode, hash);
    final cid = CID.v1(codec: codec, multihash: multihash);

    return Block._(cid: cid, data: Uint8List.fromList(data));
  }

  /// Creates a block with a pre-computed CID and data.
  ///
  /// This is useful when you already have a CID and want to create a block
  /// without recomputing the hash. Use with caution - no validation is performed
  /// to ensure the CID actually matches the data.
  factory Block.withCid(CID cid, Uint8List data) {
    return Block._(cid: cid, data: Uint8List.fromList(data));
  }

  /// The size of the block's data in bytes.
  int get size => data.length;

  /// Whether this block is empty (contains no data).
  bool get isEmpty => data.isEmpty;

  /// Whether this block contains data.
  bool get isNotEmpty => data.isNotEmpty;

  /// Validates that the block's CID matches its data.
  ///
  /// Returns true if the CID correctly identifies the data, false otherwise.
  /// This is useful for detecting corruption or tampering.
  bool validate() {
    try {
      final computedHash = _computeHash(data, cid.multihash.code);
      return _listEquals(computedHash, cid.multihash.digest);
    } catch (e) {
      return false;
    }
  }

  /// Creates a copy of this block with new data.
  ///
  /// The CID will be recomputed based on the new data.
  Block copyWithData(Uint8List newData, {int? codec, int? hashCode}) {
    return Block.fromData(
      newData,
      codec: codec ?? cid.codec,
      hashCode: hashCode ?? cid.multihash.code,
    );
  }

  /// Extracts CIDs referenced by this block's data.
  ///
  /// The implementation depends on the codec used. For example:
  /// - DAG-CBOR blocks might contain CID objects
  /// - DAG-PB blocks contain protobuf-encoded links
  /// - Raw blocks typically don't contain references
  List<CID> extractLinks() {
    switch (cid.codec) {
      case MultiCodec.raw:
        // Raw blocks don't contain structured links
        return const [];
      case MultiCodec.dagPb:
        return _extractDagPbLinks();
      case MultiCodec.dagCbor:
        return _extractDagCborLinks();
      case MultiCodec.dagJson:
        return _extractDagJsonLinks();
      default:
        // Unknown codec, assume no links
        return const [];
    }
  }

  /// Estimates the total size including referenced blocks.
  ///
  /// This provides a rough estimate of how much storage would be needed
  /// to store this block and all its dependencies. It doesn't account
  /// for deduplication or shared references.
  int estimateGraphSize([Set<String>? visited]) {
    visited ??= <String>{};

    final cidString = cid.toString();
    if (visited.contains(cidString)) {
      return 0; // Already counted
    }

    visited.add(cidString);
    int totalSize = size;

    // Add estimated size of linked blocks
    // Note: This is a rough estimate since we don't have access to the actual blocks
    final links = extractLinks();
    for (final link in links) {
      // Estimate average block size if not already visited
      if (!visited.contains(link.toString())) {
        totalSize += 1024; // Rough estimate of average block size
      }
    }

    return totalSize;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Block &&
          runtimeType == other.runtimeType &&
          cid == other.cid &&
          _listEquals(data, other.data);

  @override
  int get hashCode => Object.hash(cid, Object.hashAll(data));

  @override
  String toString() => 'Block(cid: $cid, size: ${data.length} bytes)';

  // Private helper methods

  static Uint8List _computeHash(Uint8List data, int hashCode) {
    switch (hashCode) {
      case MultiHashCode.sha256:
        return _sha256(data);
      case MultiHashCode.sha1:
        return _sha1(data);
      case MultiHashCode.sha512:
        return _sha512(data);
      case MultiHashCode.identity:
        return Uint8List.fromList(data);
      default:
        throw UnsupportedError('Hash code $hashCode not supported');
    }
  }

  static Uint8List _sha256(Uint8List data) {
    // Simplified placeholder - return fixed 32-byte hash for testing
    final hash = List<int>.filled(32, 0);
    for (int i = 0; i < data.length && i < 32; i++) {
      hash[i] = data[i];
    }
    return Uint8List.fromList(hash);
  }

  static Uint8List _sha1(Uint8List data) {
    // Simplified placeholder - return fixed 20-byte hash for testing
    final hash = List<int>.filled(20, 0);
    for (int i = 0; i < data.length && i < 20; i++) {
      hash[i] = data[i];
    }
    return Uint8List.fromList(hash);
  }

  static Uint8List _sha512(Uint8List data) {
    // Simplified placeholder - return fixed 64-byte hash for testing
    final hash = List<int>.filled(64, 0);
    for (int i = 0; i < data.length && i < 64; i++) {
      hash[i] = data[i];
    }
    return Uint8List.fromList(hash);
  }

  List<CID> _extractDagPbLinks() {
    // Parse protobuf-encoded DAG-PB format
    // This would require a proper protobuf parser
    throw UnimplementedError('DAG-PB link extraction not implemented');
  }

  List<CID> _extractDagCborLinks() {
    // Parse CBOR-encoded data for CID objects
    // This would require a CBOR parser
    throw UnimplementedError('DAG-CBOR link extraction not implemented');
  }

  List<CID> _extractDagJsonLinks() {
    // Parse JSON data for CID objects (typically in {"/": "cid"} format)
    throw UnimplementedError('DAG-JSON link extraction not implemented');
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A specialized block for storing directory information.
///
/// Directory blocks contain metadata about files and subdirectories,
/// including their names, sizes, and CIDs.
class DirectoryBlock extends Block {
  /// Creates a directory block with the given entries.
  DirectoryBlock(Map<String, DirectoryEntry> entries)
    : _entries = Map.unmodifiable(entries),
      super._(
        cid: _computeDirectoryCid(entries),
        data: _encodeDirectory(entries),
      );

  final Map<String, DirectoryEntry> _entries;

  /// The entries in this directory.
  Map<String, DirectoryEntry> get entries => _entries;

  /// Gets a directory entry by name.
  DirectoryEntry? operator [](String name) => _entries[name];

  /// Whether this directory contains an entry with the given name.
  bool contains(String name) => _entries.containsKey(name);

  /// Lists all entry names in this directory.
  Iterable<String> get names => _entries.keys;

  /// The number of entries in this directory.
  int get length => _entries.length;

  static CID _computeDirectoryCid(Map<String, DirectoryEntry> entries) {
    final data = _encodeDirectory(entries);
    final hash = Block._computeHash(data, MultiHashCode.sha256);
    final multihash = Multihash.fromDigest(MultiHashCode.sha256, hash);
    return CID.v1(codec: MultiCodec.dagPb, multihash: multihash);
  }

  static Uint8List _encodeDirectory(Map<String, DirectoryEntry> entries) {
    // Encode directory as DAG-PB protobuf
    // This is a simplified placeholder - real implementation would use protobuf
    final buffer = <int>[];

    for (final entry in entries.entries) {
      final nameBytes = entry.key.codeUnits;
      final cidBytes = entry.value.cid.bytes;

      // Simple encoding: [name_length][name][cid_length][cid][size][type]
      buffer.addAll(_encodeUint32(nameBytes.length));
      buffer.addAll(nameBytes);
      buffer.addAll(_encodeUint32(cidBytes.length));
      buffer.addAll(cidBytes);
      buffer.addAll(_encodeUint64(entry.value.size));
      buffer.add(entry.value.type.index);
    }

    return Uint8List.fromList(buffer);
  }

  static List<int> _encodeUint32(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  static List<int> _encodeUint64(int value) {
    return [
      (value >> 56) & 0xFF,
      (value >> 48) & 0xFF,
      (value >> 40) & 0xFF,
      (value >> 32) & 0xFF,
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }
}

/// Represents an entry in a directory block.
@immutable
class DirectoryEntry {
  /// Creates a directory entry.
  const DirectoryEntry({
    required this.cid,
    required this.size,
    required this.type,
    this.metadata = const {},
  });

  /// The CID of the block this entry points to.
  final CID cid;

  /// The size of the content in bytes.
  final int size;

  /// The type of entry (file or directory).
  final EntryType type;

  /// Additional metadata for this entry.
  final Map<String, dynamic> metadata;

  /// Creates a file entry.
  factory DirectoryEntry.file(
    CID cid,
    int size, [
    Map<String, dynamic>? metadata,
  ]) {
    return DirectoryEntry(
      cid: cid,
      size: size,
      type: EntryType.file,
      metadata: metadata ?? const {},
    );
  }

  /// Creates a directory entry.
  factory DirectoryEntry.directory(
    CID cid,
    int size, [
    Map<String, dynamic>? metadata,
  ]) {
    return DirectoryEntry(
      cid: cid,
      size: size,
      type: EntryType.directory,
      metadata: metadata ?? const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryEntry &&
          runtimeType == other.runtimeType &&
          cid == other.cid &&
          size == other.size &&
          type == other.type;

  @override
  int get hashCode => Object.hash(cid, size, type);

  @override
  String toString() => 'DirectoryEntry(cid: $cid, size: $size, type: $type)';
}

/// The type of a directory entry.
enum EntryType { file, directory }
