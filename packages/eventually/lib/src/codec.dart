import 'dart:typed_data';
import 'package:meta/meta.dart';

/// Interface for encoding and decoding data in different formats.
///
/// Codecs are used to transform data between its native representation
/// and the format used for storage or transmission in the Merkle DAG.
abstract interface class Codec {
  /// The codec identifier as defined in the multicodec specification.
  int get code;

  /// The name of the codec.
  String get name;

  /// Encodes data into the codec's format.
  Uint8List encode(dynamic data);

  /// Decodes data from the codec's format.
  dynamic decode(Uint8List data);

  /// Checks if the given data can be encoded by this codec.
  bool canEncode(dynamic data);

  /// Gets the MIME type associated with this codec, if applicable.
  String? get mimeType => null;
}

/// Factory for creating codec instances.
class CodecFactory {
  static final Map<int, Codec Function()> _codecs = {
    CodecType.raw: () => RawCodec(),
    CodecType.dagPb: () => DagPbCodec(),
    CodecType.dagCbor: () => DagCborCodec(),
    CodecType.dagJson: () => DagJsonCodec(),
    CodecType.json: () => JsonCodec(),
  };

  /// Creates a codec for the given codec code.
  static Codec create(int codecCode) {
    final factory = _codecs[codecCode];
    if (factory == null) {
      throw UnsupportedError('Codec $codecCode not supported');
    }
    return factory();
  }

  /// Registers a new codec factory.
  static void register(int codecCode, Codec Function() factory) {
    _codecs[codecCode] = factory;
  }

  /// Gets all supported codec codes.
  static Iterable<int> get supportedCodecs => _codecs.keys;

  /// Checks if a codec code is supported.
  static bool isSupported(int codecCode) => _codecs.containsKey(codecCode);

  /// Detects the codec type from data content.
  static int? detectCodec(Uint8List data) {
    // Try to detect codec from data patterns
    if (data.isEmpty) return CodecType.raw;

    // Check for JSON
    if (data[0] == 0x7B || data[0] == 0x5B) {
      // { or [
      try {
        final str = String.fromCharCodes(data);
        if (str.trim().startsWith('{') || str.trim().startsWith('[')) {
          return CodecType.json;
        }
      } catch (e) {
        // Not valid UTF-8, not JSON
      }
    }

    // Check for CBOR magic bytes
    if (data.length >= 1) {
      final firstByte = data[0];
      if ((firstByte & 0xE0) == 0xA0 || // map
          (firstByte & 0xE0) == 0x80 || // array
          firstByte == 0xF6 || // null
          firstByte == 0xF5 || // true
          firstByte == 0xF4) {
        // false
        return CodecType.dagCbor;
      }
    }

    // Default to raw for unknown formats
    return CodecType.raw;
  }
}

/// Common codec type constants from the multicodec specification.
class CodecType {
  static const int raw = 0x55;
  static const int dagPb = 0x70;
  static const int dagCbor = 0x71;
  static const int dagJson = 0x0129;
  static const int json = 0x0200;
  static const int cbor = 0x51;
  static const int protobuf = 0x50;
  static const int messagepack = 0x0201;
}

/// Raw codec that passes data through unchanged.
///
/// This is the simplest codec that treats data as opaque bytes.
class RawCodec implements Codec {
  @override
  int get code => CodecType.raw;

  @override
  String get name => 'raw';

  @override
  String get mimeType => 'application/octet-stream';

  @override
  Uint8List encode(dynamic data) {
    if (data is Uint8List) {
      return Uint8List.fromList(data);
    } else if (data is List<int>) {
      return Uint8List.fromList(data);
    } else if (data is String) {
      return Uint8List.fromList(data.codeUnits);
    } else {
      throw ArgumentError('Raw codec can only encode byte data or strings');
    }
  }

  @override
  dynamic decode(Uint8List data) {
    return Uint8List.fromList(data);
  }

  @override
  bool canEncode(dynamic data) {
    return data is Uint8List || data is List<int> || data is String;
  }
}

/// DAG-PB (Protocol Buffers) codec for IPFS-style directory structures.
///
/// This is a placeholder implementation - a real version would use
/// proper protobuf encoding/decoding.
class DagPbCodec implements Codec {
  @override
  int get code => CodecType.dagPb;

  @override
  String get name => 'dag-pb';

  @override
  String get mimeType => 'application/x-protobuf';

  @override
  Uint8List encode(dynamic data) {
    if (data is DagPbNode) {
      return _encodeDagPbNode(data);
    }
    throw ArgumentError('DAG-PB codec can only encode DagPbNode objects');
  }

  @override
  dynamic decode(Uint8List data) {
    return _decodeDagPbNode(data);
  }

  @override
  bool canEncode(dynamic data) {
    return data is DagPbNode;
  }

  Uint8List _encodeDagPbNode(DagPbNode node) {
    // Simplified DAG-PB encoding
    // In a real implementation, this would use proper protobuf
    final buffer = <int>[];

    // Encode data field
    if (node.data.isNotEmpty) {
      buffer.addAll(
        _encodeVarint(1 << 3 | 2),
      ); // field 1, wire type 2 (length-delimited)
      buffer.addAll(_encodeVarint(node.data.length));
      buffer.addAll(node.data);
    }

    // Encode links
    for (final link in node.links) {
      buffer.addAll(_encodeVarint(2 << 3 | 2)); // field 2, wire type 2
      final linkData = _encodeDagPbLink(link);
      buffer.addAll(_encodeVarint(linkData.length));
      buffer.addAll(linkData);
    }

    return Uint8List.fromList(buffer);
  }

  Uint8List _encodeDagPbLink(DagPbLink link) {
    final buffer = <int>[];

    // Hash field
    buffer.addAll(_encodeVarint(1 << 3 | 2));
    buffer.addAll(_encodeVarint(link.hash.length));
    buffer.addAll(link.hash);

    // Name field
    if (link.name.isNotEmpty) {
      final nameBytes = link.name.codeUnits;
      buffer.addAll(_encodeVarint(2 << 3 | 2));
      buffer.addAll(_encodeVarint(nameBytes.length));
      buffer.addAll(nameBytes);
    }

    // Size field
    if (link.size > 0) {
      buffer.addAll(_encodeVarint(3 << 3 | 0)); // wire type 0 (varint)
      buffer.addAll(_encodeVarint(link.size));
    }

    return Uint8List.fromList(buffer);
  }

  DagPbNode _decodeDagPbNode(Uint8List data) {
    // Simplified DAG-PB decoding
    throw UnimplementedError('DAG-PB decoding not implemented');
  }

  List<int> _encodeVarint(int value) {
    final bytes = <int>[];
    while (value >= 0x80) {
      bytes.add((value & 0xFF) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0xFF);
    return bytes;
  }
}

/// DAG-CBOR codec for structured data with CID links.
///
/// This is a placeholder implementation - a real version would use
/// proper CBOR encoding/decoding with CID support.
class DagCborCodec implements Codec {
  @override
  int get code => CodecType.dagCbor;

  @override
  String get name => 'dag-cbor';

  @override
  String get mimeType => 'application/cbor';

  @override
  Uint8List encode(dynamic data) {
    // TODO: Implement CBOR encoding with CID link support
    throw UnimplementedError('DAG-CBOR encoding not implemented');
  }

  @override
  dynamic decode(Uint8List data) {
    // TODO: Implement CBOR decoding with CID link support
    throw UnimplementedError('DAG-CBOR decoding not implemented');
  }

  @override
  bool canEncode(dynamic data) {
    // CBOR can encode most basic types
    return data is Map ||
        data is List ||
        data is String ||
        data is int ||
        data is double ||
        data is bool ||
        data == null;
  }
}

/// DAG-JSON codec for JSON data with CID links.
class DagJsonCodec implements Codec {
  @override
  int get code => CodecType.dagJson;

  @override
  String get name => 'dag-json';

  @override
  String get mimeType => 'application/json';

  @override
  Uint8List encode(dynamic data) {
    // TODO: Implement JSON encoding with CID link support
    // CID links are typically represented as {"/": "cid_string"}
    throw UnimplementedError('DAG-JSON encoding not implemented');
  }

  @override
  dynamic decode(Uint8List data) {
    // TODO: Implement JSON decoding with CID link support
    throw UnimplementedError('DAG-JSON decoding not implemented');
  }

  @override
  bool canEncode(dynamic data) {
    return data is Map ||
        data is List ||
        data is String ||
        data is int ||
        data is double ||
        data is bool ||
        data == null;
  }
}

/// Regular JSON codec without CID link support.
class JsonCodec implements Codec {
  @override
  int get code => CodecType.json;

  @override
  String get name => 'json';

  @override
  String get mimeType => 'application/json';

  @override
  Uint8List encode(dynamic data) {
    // TODO: Implement standard JSON encoding
    throw UnimplementedError('JSON encoding not implemented');
  }

  @override
  dynamic decode(Uint8List data) {
    // TODO: Implement standard JSON decoding
    throw UnimplementedError('JSON decoding not implemented');
  }

  @override
  bool canEncode(dynamic data) {
    return data is Map ||
        data is List ||
        data is String ||
        data is int ||
        data is double ||
        data is bool ||
        data == null;
  }
}

/// Represents a DAG-PB node structure.
@immutable
class DagPbNode {
  /// Creates a DAG-PB node.
  const DagPbNode({required this.data, required this.links});

  /// The data contained in this node.
  final Uint8List data;

  /// Links to other nodes.
  final List<DagPbLink> links;

  /// Creates an empty DAG-PB node.
  factory DagPbNode.empty() {
    return DagPbNode(data: Uint8List(0), links: const []);
  }

  /// Creates a DAG-PB node with only data.
  factory DagPbNode.withData(Uint8List data) {
    return DagPbNode(data: data, links: const []);
  }

  /// Creates a copy of this node with new properties.
  DagPbNode copyWith({Uint8List? data, List<DagPbLink>? links}) {
    return DagPbNode(data: data ?? this.data, links: links ?? this.links);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DagPbNode &&
          runtimeType == other.runtimeType &&
          _listEquals(data, other.data) &&
          _listEquals(links, other.links);

  @override
  int get hashCode => Object.hash(Object.hashAll(data), Object.hashAll(links));

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Represents a link in a DAG-PB node.
@immutable
class DagPbLink {
  /// Creates a DAG-PB link.
  const DagPbLink({required this.hash, required this.name, required this.size});

  /// The hash (CID) of the linked node.
  final Uint8List hash;

  /// The name of the link.
  final String name;

  /// The cumulative size of the linked node and its dependencies.
  final int size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DagPbLink &&
          runtimeType == other.runtimeType &&
          _listEquals(hash, other.hash) &&
          name == other.name &&
          size == other.size;

  @override
  int get hashCode => Object.hash(Object.hashAll(hash), name, size);

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'DagPbLink(name: $name, size: $size)';
}

/// Exception thrown when codec operations fail.
class CodecException implements Exception {
  const CodecException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'CodecException: $message (caused by: $cause)';
    }
    return 'CodecException: $message';
  }
}

/// Exception thrown when trying to use an unsupported codec.
class UnsupportedCodecException extends CodecException {
  const UnsupportedCodecException(int codecCode)
    : super('Unsupported codec: $codecCode');
}
