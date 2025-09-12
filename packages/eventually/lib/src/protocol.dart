import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'peer.dart';

/// Interface for synchronization protocols used in Merkle DAG systems.
///
/// Protocols define the message formats for exchanging blocks and maintaining
/// consistency in distributed content-addressed storage systems.
abstract interface class SyncProtocol {
  /// The name of the protocol.
  String get name;

  /// The version of the protocol.
  String get version;

  /// The capabilities supported by this protocol.
  Set<String> get capabilities;

  /// Creates a protocol message from raw bytes.
  SyncMessage? decodeMessage(Uint8List data);

  /// Encodes a protocol message to bytes.
  Uint8List encodeMessage(SyncMessage message);
}

/// Result of protocol negotiation.
@immutable
class ProtocolNegotiation {
  /// Creates a protocol negotiation result.
  const ProtocolNegotiation({
    required this.success,
    required this.agreedVersion,
    required this.capabilities,
    this.parameters = const {},
    this.error,
  });

  /// Whether negotiation was successful.
  final bool success;

  /// The protocol version both peers agreed on.
  final String agreedVersion;

  /// The capabilities both peers support.
  final Set<String> capabilities;

  /// Additional negotiated parameters.
  final Map<String, dynamic> parameters;

  /// Error message if negotiation failed.
  final String? error;

  @override
  String toString() =>
      'ProtocolNegotiation('
      'success: $success, '
      'version: $agreedVersion, '
      'capabilities: ${capabilities.length}'
      ')';
}

/// Message format validation and encoding utilities.
class ProtocolUtils {
  /// Validates that a message follows the protocol format.
  static bool isValidMessage(SyncMessage message) {
    switch (message.type) {
      case 'have':
        return message is Have && message.cids.isNotEmpty;
      case 'want':
        return message is Want && message.cids.isNotEmpty;
      case 'block_request':
        return message is BlockRequest;
      case 'block_response':
        return message is BlockResponse;
      default:
        return false;
    }
  }

  /// Gets the estimated size of a message in bytes.
  static int estimateMessageSize(SyncMessage message) {
    final baseSize = message.type.length + 4; // type + separators

    return switch (message) {
      Have have =>
        baseSize + have.cids.fold(0, (sum, cid) => sum + cid.bytes.length),
      Want want =>
        baseSize + want.cids.fold(0, (sum, cid) => sum + cid.bytes.length),
      BlockRequest request => baseSize + request.cid.bytes.length,
      BlockResponse response =>
        baseSize + response.block.cid.bytes.length + response.block.size,
    };
  }
}

/// BitSwap-inspired protocol for block exchange.
///
/// This protocol implements a simplified version of IPFS BitSwap,
/// where peers exchange want lists and provide blocks on demand.
class BitSwapProtocol implements SyncProtocol {
  /// Creates a BitSwap protocol instance.
  const BitSwapProtocol();

  @override
  String get name => 'bitswap';

  @override
  String get version => '1.0.0';

  @override
  Set<String> get capabilities => const {
    'want-blocks',
    'send-blocks',
    'have-blocks',
    'priority-requests',
  };

  @override
  SyncMessage? decodeMessage(Uint8List data) {
    return SyncMessageCodec.decode(data);
  }

  @override
  Uint8List encodeMessage(SyncMessage message) {
    return message.toBytes();
  }
}

/// Exception thrown when protocol operations fail.
class ProtocolException implements Exception {
  /// Creates a protocol exception.
  const ProtocolException(this.message, {this.cause});

  /// The error message.
  final String message;

  /// The underlying cause of the error.
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'ProtocolException: $message (caused by: $cause)';
    }
    return 'ProtocolException: $message';
  }
}

/// Exception thrown when message decoding fails.
class MessageDecodingException extends ProtocolException {
  /// Creates a message decoding exception.
  const MessageDecodingException(String message, {super.cause})
    : super(message);
}
