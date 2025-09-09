import 'dart:typed_data';
import 'package:meta/meta.dart';

/// Content Identifier (CID) implementation based on the IPFS specification.
///
/// A CID is a self-describing content-addressed identifier that uniquely
/// identifies content in a distributed system. It contains:
/// - Version (currently supports v0 and v1)
/// - Codec (how the content is encoded)
/// - Multihash (cryptographic hash of the content)
@immutable
class CID {
  /// Creates a CID from its components.
  const CID._({
    required this.version,
    required this.codec,
    required this.multihash,
    required Uint8List bytes,
    required String string,
  }) : _bytes = bytes,
       _string = string;

  /// The CID version (0 or 1).
  final int version;

  /// The codec identifier (how the content is encoded).
  final int codec;

  /// The multihash of the content.
  final Multihash multihash;

  final Uint8List _bytes;
  final String _string;

  /// Creates a CID v1 with the given codec and multihash.
  factory CID.v1({required int codec, required Multihash multihash}) {
    return CID._fromComponents(version: 1, codec: codec, multihash: multihash);
  }

  /// Creates a CID v0 (legacy format, DAG-PB codec only).
  factory CID.v0(Multihash multihash) {
    if (multihash.code != MultiHashCode.sha256) {
      throw ArgumentError('CID v0 only supports SHA-256 hashes');
    }
    if (multihash.digest.length != 32) {
      throw ArgumentError('CID v0 requires 32-byte SHA-256 hash');
    }

    return CID._fromComponents(
      version: 0,
      codec: MultiCodec.dagPb,
      multihash: multihash,
    );
  }

  /// Creates a CID from a string representation.
  factory CID.parse(String cidString) {
    try {
      // Try base58 first (CID v0)
      if (_isBase58(cidString)) {
        final bytes = _base58Decode(cidString);
        if (bytes.length == 34 && bytes[0] == 0x12 && bytes[1] == 0x20) {
          final hash = Multihash.fromBytes(bytes);
          return CID.v0(hash);
        }
      }

      // Try multibase for CID v1
      final (base, data) = _decodeMultibase(cidString);
      return CID.fromBytes(data);
    } catch (e) {
      throw FormatException('Invalid CID format: $cidString', e);
    }
  }

  /// Creates a CID from its binary representation.
  factory CID.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('CID bytes cannot be empty');
    }

    // Check if this is a CID v0 (34 bytes, starts with 0x12, 0x20)
    if (bytes.length == 34 && bytes[0] == 0x12 && bytes[1] == 0x20) {
      final multihash = Multihash.fromBytes(bytes);
      return CID.v0(multihash);
    }

    // Parse as CID v1
    int offset = 0;
    final version = _readVarint(bytes, offset);
    offset += _varintSize(version);

    if (version != 1) {
      throw FormatException('Unsupported CID version: $version');
    }

    final codec = _readVarint(bytes, offset);
    offset += _varintSize(codec);

    final multihashBytes = bytes.sublist(offset);
    final multihash = Multihash.fromBytes(multihashBytes);

    return CID._fromComponents(
      version: version,
      codec: codec,
      multihash: multihash,
    );
  }

  /// Internal constructor that computes bytes and string representations.
  factory CID._fromComponents({
    required int version,
    required int codec,
    required Multihash multihash,
  }) {
    late final Uint8List bytes;
    late final String string;

    if (version == 0) {
      // CID v0 is just the multihash
      bytes = multihash.bytes;
      string = _base58Encode(bytes);
    } else {
      // CID v1 format: version + codec + multihash
      final versionBytes = _encodeVarint(version);
      final codecBytes = _encodeVarint(codec);

      bytes = Uint8List.fromList([
        ...versionBytes,
        ...codecBytes,
        ...multihash.bytes,
      ]);

      // Encode as multibase with base32
      string = _encodeMultibase('b', bytes);
    }

    return CID._(
      version: version,
      codec: codec,
      multihash: multihash,
      bytes: bytes,
      string: string,
    );
  }

  /// Returns the binary representation of this CID.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Returns the string representation of this CID.
  @override
  String toString() => _string;

  /// Returns the hash digest as bytes.
  Uint8List get hash => multihash.digest;

  /// Returns the hash algorithm code.
  int get hashAlgorithm => multihash.code;

  /// Returns the hash size in bytes.
  int get hashSize => multihash.size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CID &&
          runtimeType == other.runtimeType &&
          version == other.version &&
          codec == other.codec &&
          multihash == other.multihash;

  @override
  int get hashCode => Object.hash(version, codec, multihash);

  // Utility methods for encoding/decoding

  static bool _isBase58(String s) {
    return RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(s);
  }

  static Uint8List _base58Decode(String input) {
    // Simplified placeholder - just return empty bytes for now
    return Uint8List(0);
  }

  static String _base58Encode(Uint8List bytes) {
    // Simplified placeholder - return hex representation for now
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static (String, Uint8List) _decodeMultibase(String input) {
    if (input.isEmpty) throw FormatException('Empty multibase string');

    final base = input[0];
    final data = input.substring(1);

    switch (base) {
      case 'b': // base32
        return (base, _base32Decode(data));
      case 'z': // base58btc
        return (base, _base58Decode(data));
      default:
        throw FormatException('Unsupported multibase: $base');
    }
  }

  static String _encodeMultibase(String base, Uint8List bytes) {
    switch (base) {
      case 'b': // base32
        return 'b${_base32Encode(bytes)}';
      case 'z': // base58btc
        return 'z${_base58Encode(bytes)}';
      default:
        throw ArgumentError('Unsupported multibase: $base');
    }
  }

  static Uint8List _base32Decode(String input) {
    // Simplified placeholder - just return empty bytes for now
    return Uint8List(0);
  }

  static String _base32Encode(Uint8List bytes) {
    // Simplified placeholder - return hex representation for now
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static int _readVarint(Uint8List bytes, int offset) {
    int result = 0;
    int shift = 0;

    for (int i = offset; i < bytes.length; i++) {
      final byte = bytes[i];
      result |= (byte & 0x7F) << shift;

      if ((byte & 0x80) == 0) {
        return result;
      }

      shift += 7;
      if (shift >= 32) {
        throw FormatException('Varint too long');
      }
    }

    throw FormatException('Incomplete varint');
  }

  static int _varintSize(int value) {
    int size = 0;
    do {
      value >>= 7;
      size++;
    } while (value != 0);
    return size;
  }

  static Uint8List _encodeVarint(int value) {
    final bytes = <int>[];

    while (value >= 0x80) {
      bytes.add((value & 0xFF) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0xFF);

    return Uint8List.fromList(bytes);
  }
}

/// Multihash implementation for content addressing.
@immutable
class Multihash {
  /// Creates a multihash from its components.
  const Multihash._({
    required this.code,
    required this.size,
    required this.digest,
    required Uint8List bytes,
  }) : _bytes = bytes;

  /// The hash algorithm code.
  final int code;

  /// The hash size in bytes.
  final int size;

  /// The hash digest.
  final Uint8List digest;

  final Uint8List _bytes;

  /// Creates a multihash from algorithm code and digest.
  factory Multihash.fromDigest(int code, Uint8List digest) {
    final size = digest.length;
    final sizeBytes = CID._encodeVarint(size);
    final codeBytes = CID._encodeVarint(code);

    final bytes = Uint8List.fromList([...codeBytes, ...sizeBytes, ...digest]);

    return Multihash._(
      code: code,
      size: size,
      digest: Uint8List.fromList(digest),
      bytes: bytes,
    );
  }

  /// Creates a multihash from its binary representation.
  factory Multihash.fromBytes(Uint8List bytes) {
    if (bytes.length < 3) {
      throw ArgumentError('Multihash too short');
    }

    int offset = 0;
    final code = CID._readVarint(bytes, offset);
    offset += CID._varintSize(code);

    final size = CID._readVarint(bytes, offset);
    offset += CID._varintSize(size);

    if (bytes.length < offset + size) {
      throw ArgumentError('Multihash digest too short');
    }

    final digest = bytes.sublist(offset, offset + size);

    return Multihash._(
      code: code,
      size: size,
      digest: digest,
      bytes: Uint8List.fromList(bytes),
    );
  }

  /// Returns the binary representation of this multihash.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Multihash &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          size == other.size &&
          _listEquals(digest, other.digest);

  @override
  int get hashCode => Object.hash(code, size, Object.hashAll(digest));

  @override
  String toString() => 'Multihash(code: $code, size: $size)';

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Common hash algorithm codes.
class MultiHashCode {
  static const int identity = 0x00;
  static const int sha1 = 0x11;
  static const int sha256 = 0x12;
  static const int sha512 = 0x13;
  static const int blake2b256 = 0xb220;
  static const int blake2s256 = 0xb260;
}

/// Common codec identifiers.
class MultiCodec {
  static const int raw = 0x55;
  static const int dagPb = 0x70;
  static const int dagCbor = 0x71;
  static const int dagJson = 0x0129;
  static const int gitRaw = 0x78;
}
