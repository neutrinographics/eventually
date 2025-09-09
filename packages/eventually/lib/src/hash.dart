import 'dart:typed_data';
import 'package:meta/meta.dart';

/// Interface for hash functions used in content addressing.
///
/// Hash functions provide cryptographic digests of data, which are used
/// to create content identifiers (CIDs) and ensure data integrity.
abstract interface class Hasher {
  /// The hash algorithm code as defined in the multihash specification.
  int get code;

  /// The name of the hash algorithm.
  String get name;

  /// The size of the hash digest in bytes.
  int get digestSize;

  /// Computes the hash of the given data.
  Uint8List hash(Uint8List data);

  /// Creates a streaming hasher for incremental hashing.
  StreamingHasher createStreaming();
}

/// Interface for streaming hash computation.
///
/// Allows data to be fed incrementally to the hasher, which is useful
/// for large files or streaming data.
abstract interface class StreamingHasher {
  /// Adds data to the hash computation.
  void update(Uint8List data);

  /// Finalizes the hash computation and returns the digest.
  Uint8List finish();

  /// Resets the hasher to its initial state.
  void reset();
}

/// Factory for creating hash instances.
class HashFactory {
  static final Map<int, Hasher Function()> _hashers = {
    HashCode.identity: () => IdentityHasher(),
    HashCode.sha256: () => Sha256Hasher(),
    HashCode.sha1: () => Sha1Hasher(),
    HashCode.sha512: () => Sha512Hasher(),
  };

  /// Creates a hasher for the given hash code.
  static Hasher create(int hashCode) {
    final factory = _hashers[hashCode];
    if (factory == null) {
      throw UnsupportedError('Hash code $hashCode not supported');
    }
    return factory();
  }

  /// Registers a new hasher factory.
  static void register(int hashCode, Hasher Function() factory) {
    _hashers[hashCode] = factory;
  }

  /// Gets all supported hash codes.
  static Iterable<int> get supportedHashCodes => _hashers.keys;

  /// Checks if a hash code is supported.
  static bool isSupported(int hashCode) => _hashers.containsKey(hashCode);
}

/// Common hash algorithm codes from the multihash specification.
class HashCode {
  static const int identity = 0x00;
  static const int sha1 = 0x11;
  static const int sha256 = 0x12;
  static const int sha512 = 0x13;
  static const int sha3224 = 0x17;
  static const int sha3256 = 0x16;
  static const int sha3384 = 0x15;
  static const int sha3512 = 0x14;
  static const int blake2b256 = 0xb220;
  static const int blake2s256 = 0xb260;
  static const int xxhash32 = 0xb3;
  static const int xxhash64 = 0xb4;
}

/// Identity hasher that returns the input data unchanged.
///
/// This is mainly used for small data that doesn't need cryptographic hashing.
class IdentityHasher implements Hasher {
  @override
  int get code => HashCode.identity;

  @override
  String get name => 'identity';

  @override
  int get digestSize => -1; // Variable size

  @override
  Uint8List hash(Uint8List data) {
    return Uint8List.fromList(data);
  }

  @override
  StreamingHasher createStreaming() {
    return _IdentityStreamingHasher();
  }
}

class _IdentityStreamingHasher implements StreamingHasher {
  final List<int> _buffer = [];

  @override
  void update(Uint8List data) {
    _buffer.addAll(data);
  }

  @override
  Uint8List finish() {
    return Uint8List.fromList(_buffer);
  }

  @override
  void reset() {
    _buffer.clear();
  }
}

/// Placeholder SHA-256 hasher.
///
/// In a real implementation, this would use the crypto package or
/// a similar cryptographic library.
class Sha256Hasher implements Hasher {
  @override
  int get code => HashCode.sha256;

  @override
  String get name => 'sha256';

  @override
  int get digestSize => 32;

  @override
  Uint8List hash(Uint8List data) {
    // TODO: Implement actual SHA-256 hashing
    // For now, return a placeholder hash
    throw UnimplementedError('SHA-256 hashing not implemented');
  }

  @override
  StreamingHasher createStreaming() {
    return _Sha256StreamingHasher();
  }
}

class _Sha256StreamingHasher implements StreamingHasher {
  final List<int> _buffer = [];

  @override
  void update(Uint8List data) {
    _buffer.addAll(data);
  }

  @override
  Uint8List finish() {
    // TODO: Implement actual SHA-256 hashing
    throw UnimplementedError('SHA-256 streaming hashing not implemented');
  }

  @override
  void reset() {
    _buffer.clear();
  }
}

/// Placeholder SHA-1 hasher.
class Sha1Hasher implements Hasher {
  @override
  int get code => HashCode.sha1;

  @override
  String get name => 'sha1';

  @override
  int get digestSize => 20;

  @override
  Uint8List hash(Uint8List data) {
    throw UnimplementedError('SHA-1 hashing not implemented');
  }

  @override
  StreamingHasher createStreaming() {
    return _Sha1StreamingHasher();
  }
}

class _Sha1StreamingHasher implements StreamingHasher {
  final List<int> _buffer = [];

  @override
  void update(Uint8List data) {
    _buffer.addAll(data);
  }

  @override
  Uint8List finish() {
    throw UnimplementedError('SHA-1 streaming hashing not implemented');
  }

  @override
  void reset() {
    _buffer.clear();
  }
}

/// Placeholder SHA-512 hasher.
class Sha512Hasher implements Hasher {
  @override
  int get code => HashCode.sha512;

  @override
  String get name => 'sha512';

  @override
  int get digestSize => 64;

  @override
  Uint8List hash(Uint8List data) {
    throw UnimplementedError('SHA-512 hashing not implemented');
  }

  @override
  StreamingHasher createStreaming() {
    return _Sha512StreamingHasher();
  }
}

class _Sha512StreamingHasher implements StreamingHasher {
  final List<int> _buffer = [];

  @override
  void update(Uint8List data) {
    _buffer.addAll(data);
  }

  @override
  Uint8List finish() {
    throw UnimplementedError('SHA-512 streaming hashing not implemented');
  }

  @override
  void reset() {
    _buffer.clear();
  }
}

/// Utility functions for working with hashes.
class HashUtils {
  /// Converts a hash digest to a hexadecimal string.
  static String toHex(Uint8List hash) {
    return hash.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Converts a hexadecimal string to a hash digest.
  static Uint8List fromHex(String hex) {
    if (hex.length % 2 != 0) {
      throw ArgumentError('Hex string must have even length');
    }

    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      final byteString = hex.substring(i, i + 2);
      bytes.add(int.parse(byteString, radix: 16));
    }

    return Uint8List.fromList(bytes);
  }

  /// Compares two hash digests for equality.
  static bool equals(Uint8List hash1, Uint8List hash2) {
    if (hash1.length != hash2.length) return false;

    for (int i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) return false;
    }

    return true;
  }

  /// Computes the hash of data using the specified algorithm.
  static Uint8List computeHash(Uint8List data, int hashCode) {
    final hasher = HashFactory.create(hashCode);
    return hasher.hash(data);
  }

  /// Verifies that data matches the expected hash.
  static bool verifyHash(Uint8List data, Uint8List expectedHash, int hashCode) {
    final actualHash = computeHash(data, hashCode);
    return equals(actualHash, expectedHash);
  }
}

/// Exception thrown when hash operations fail.
class HashException implements Exception {
  const HashException(this.message);

  final String message;

  @override
  String toString() => 'HashException: $message';
}

/// Exception thrown when an unsupported hash algorithm is used.
class UnsupportedHashException extends HashException {
  const UnsupportedHashException(int hashCode)
    : super('Unsupported hash algorithm: $hashCode');
}
