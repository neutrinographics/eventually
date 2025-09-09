import 'dart:async';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'block.dart';
import 'cid.dart';
import 'peer.dart';

/// Interface for synchronization protocols used in Merkle DAG systems.
///
/// Protocols define how peers communicate to exchange blocks and maintain
/// consistency in distributed content-addressed storage systems.
abstract interface class SyncProtocol {
  /// The name of the protocol.
  String get name;

  /// The version of the protocol.
  String get version;

  /// The capabilities supported by this protocol.
  Set<String> get capabilities;

  /// Negotiates protocol parameters with a peer.
  ///
  /// This is called during the initial handshake to establish
  /// communication parameters and capabilities.
  Future<ProtocolNegotiation> negotiate(
    PeerConnection connection,
    Map<String, dynamic> parameters,
  );

  /// Initiates synchronization with a peer.
  ///
  /// This method starts the protocol exchange to synchronize
  /// the given roots with the peer.
  Future<SyncSession> startSync(
    PeerConnection connection,
    Set<CID> roots, {
    Map<String, dynamic>? options,
  });

  /// Handles an incoming sync request from a peer.
  ///
  /// This is called when a peer initiates synchronization with us.
  Future<SyncSession> handleSyncRequest(
    PeerConnection connection,
    SyncRequest request,
  );

  /// Creates a protocol message from raw bytes.
  ProtocolMessage decodeMessage(Uint8List data);

  /// Encodes a protocol message to bytes.
  Uint8List encodeMessage(ProtocolMessage message);
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

/// Represents an active synchronization session.
abstract interface class SyncSession {
  /// The peer this session is with.
  Peer get peer;

  /// The protocol being used.
  SyncProtocol get protocol;

  /// The current state of the session.
  SessionState get state;

  /// Stream of session events.
  Stream<SessionEvent> get events;

  /// Requests specific blocks from the peer.
  Future<void> requestBlocks(Set<CID> cids);

  /// Sends blocks to the peer.
  Future<void> sendBlocks(Set<Block> blocks);

  /// Announces available blocks to the peer.
  Future<void> announceBlocks(Set<CID> cids);

  /// Gets the session statistics.
  SessionStats get stats;

  /// Closes the session gracefully.
  Future<void> close();

  /// Aborts the session immediately.
  Future<void> abort([String? reason]);
}

/// State of a synchronization session.
enum SessionState {
  /// Session is initializing.
  initializing,

  /// Session is actively synchronizing.
  active,

  /// Session is completing.
  completing,

  /// Session has completed successfully.
  completed,

  /// Session has failed.
  failed,

  /// Session has been aborted.
  aborted,

  /// Session is closed.
  closed,
}

/// Base class for protocol messages.
@immutable
sealed class ProtocolMessage {
  /// Creates a protocol message.
  ProtocolMessage({required this.type, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// The type of message.
  final String type;

  /// When the message was created.
  final DateTime timestamp;

  /// Converts the message to bytes for transmission.
  Uint8List toBytes();

  /// Creates a message from bytes.
  static ProtocolMessage fromBytes(Uint8List bytes) {
    throw UnimplementedError('fromBytes must be implemented by subclasses');
  }
}

/// Request to start synchronization.
@immutable
final class SyncRequest extends ProtocolMessage {
  /// Creates a sync request.
  SyncRequest({required this.roots, required this.options, DateTime? timestamp})
    : super(type: 'sync_request', timestamp: timestamp);

  /// The root CIDs to synchronize.
  final Set<CID> roots;

  /// Additional options for the sync.
  final Map<String, dynamic> options;

  @override
  Uint8List toBytes() {
    // Simple encoding for demonstration
    final typeBytes = type.codeUnits;
    final buffer = <int>[...typeBytes, 0x00];

    for (final root in roots) {
      buffer.addAll(root.bytes);
      buffer.add(0x00);
    }

    return Uint8List.fromList(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncRequest &&
          runtimeType == other.runtimeType &&
          roots == other.roots &&
          options == other.options;

  @override
  int get hashCode => Object.hash(roots, options);
}

/// Response to a sync request.
@immutable
final class SyncResponse extends ProtocolMessage {
  /// Creates a sync response.
  SyncResponse({
    required this.accepted,
    required this.sessionId,
    this.reason,
    DateTime? timestamp,
  }) : super(type: 'sync_response', timestamp: timestamp);

  /// Whether the sync request was accepted.
  final bool accepted;

  /// The session ID for the sync (if accepted).
  final String? sessionId;

  /// Reason for rejection (if not accepted).
  final String? reason;

  @override
  Uint8List toBytes() {
    final typeBytes = type.codeUnits;
    final acceptedByte = accepted ? 1 : 0;
    final buffer = <int>[...typeBytes, 0x00, acceptedByte];

    if (sessionId != null) {
      buffer.add(0x00);
      buffer.addAll(sessionId!.codeUnits);
    }

    return Uint8List.fromList(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncResponse &&
          runtimeType == other.runtimeType &&
          accepted == other.accepted &&
          sessionId == other.sessionId &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(accepted, sessionId, reason);
}

/// Message announcing available blocks.
@immutable
final class BlockAnnouncement extends ProtocolMessage {
  /// Creates a block announcement.
  BlockAnnouncement({required this.cids, DateTime? timestamp})
    : super(type: 'block_announcement', timestamp: timestamp);

  /// The CIDs being announced.
  final Set<CID> cids;

  @override
  Uint8List toBytes() {
    final typeBytes = type.codeUnits;
    final buffer = <int>[...typeBytes, 0x00];

    for (final cid in cids) {
      buffer.addAll(cid.bytes);
      buffer.add(0x00);
    }

    return Uint8List.fromList(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockAnnouncement &&
          runtimeType == other.runtimeType &&
          cids == other.cids;

  @override
  int get hashCode => Object.hashAll(cids);
}

/// Message requesting specific blocks.
@immutable
final class BlockRequestMessage extends ProtocolMessage {
  /// Creates a block request message.
  BlockRequestMessage({
    required this.cids,
    required this.priority,
    DateTime? timestamp,
  }) : super(type: 'block_request', timestamp: timestamp);

  /// The CIDs being requested.
  final Set<CID> cids;

  /// Priority of the request (higher = more urgent).
  final int priority;

  @override
  Uint8List toBytes() {
    final typeBytes = type.codeUnits;
    final priorityBytes = _encodeInt32(priority);
    final buffer = <int>[...typeBytes, 0x00, ...priorityBytes, 0x00];

    for (final cid in cids) {
      buffer.addAll(cid.bytes);
      buffer.add(0x00);
    }

    return Uint8List.fromList(buffer);
  }

  static List<int> _encodeInt32(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockRequestMessage &&
          runtimeType == other.runtimeType &&
          cids == other.cids &&
          priority == other.priority;

  @override
  int get hashCode => Object.hash(Object.hashAll(cids), priority);
}

/// Message containing blocks in response to a request.
@immutable
final class BlockDelivery extends ProtocolMessage {
  /// Creates a block delivery message.
  BlockDelivery({required this.blocks, DateTime? timestamp})
    : super(type: 'block_delivery', timestamp: timestamp);

  /// The blocks being delivered.
  final Set<Block> blocks;

  @override
  Uint8List toBytes() {
    final typeBytes = type.codeUnits;
    final buffer = <int>[...typeBytes, 0x00];

    for (final block in blocks) {
      final cidBytes = block.cid.bytes;
      final dataBytes = block.data;

      buffer.addAll(_encodeInt32(cidBytes.length));
      buffer.addAll(cidBytes);
      buffer.addAll(_encodeInt32(dataBytes.length));
      buffer.addAll(dataBytes);
    }

    return Uint8List.fromList(buffer);
  }

  static List<int> _encodeInt32(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockDelivery &&
          runtimeType == other.runtimeType &&
          blocks == other.blocks;

  @override
  int get hashCode => Object.hashAll(blocks);
}

/// Session events that can occur during synchronization.
@immutable
sealed class SessionEvent {
  /// Creates a session event.
  const SessionEvent({required this.timestamp});

  /// When the event occurred.
  final DateTime timestamp;
}

/// Event when session state changes.
@immutable
final class SessionStateChanged extends SessionEvent {
  /// Creates a session state changed event.
  const SessionStateChanged({
    required this.oldState,
    required this.newState,
    required super.timestamp,
  });

  /// The previous state.
  final SessionState oldState;

  /// The new state.
  final SessionState newState;
}

/// Event when blocks are requested.
@immutable
final class BlocksRequested extends SessionEvent {
  /// Creates a blocks requested event.
  const BlocksRequested({required this.cids, required super.timestamp});

  /// The CIDs that were requested.
  final Set<CID> cids;
}

/// Event when blocks are received.
@immutable
final class BlocksReceived extends SessionEvent {
  /// Creates a blocks received event.
  const BlocksReceived({required this.blocks, required super.timestamp});

  /// The blocks that were received.
  final Set<Block> blocks;
}

/// Event when blocks are sent.
@immutable
final class BlocksSent extends SessionEvent {
  /// Creates a blocks sent event.
  const BlocksSent({required this.blocks, required super.timestamp});

  /// The blocks that were sent.
  final Set<Block> blocks;
}

/// Statistics for a sync session.
@immutable
class SessionStats {
  /// Creates session statistics.
  const SessionStats({
    required this.blocksRequested,
    required this.blocksReceived,
    required this.blocksSent,
    required this.bytesReceived,
    required this.bytesSent,
    required this.duration,
    required this.messagesExchanged,
  });

  /// Number of blocks requested.
  final int blocksRequested;

  /// Number of blocks received.
  final int blocksReceived;

  /// Number of blocks sent.
  final int blocksSent;

  /// Total bytes received.
  final int bytesReceived;

  /// Total bytes sent.
  final int bytesSent;

  /// Duration of the session.
  final Duration duration;

  /// Total messages exchanged.
  final int messagesExchanged;

  /// Creates empty statistics.
  factory SessionStats.empty() {
    return const SessionStats(
      blocksRequested: 0,
      blocksReceived: 0,
      blocksSent: 0,
      bytesReceived: 0,
      bytesSent: 0,
      duration: Duration.zero,
      messagesExchanged: 0,
    );
  }

  @override
  String toString() =>
      'SessionStats('
      'requested: $blocksRequested, '
      'received: $blocksReceived, '
      'sent: $blocksSent, '
      'bytes: ${bytesReceived + bytesSent}, '
      'messages: $messagesExchanged, '
      'duration: ${duration.inSeconds}s'
      ')';
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
  Future<ProtocolNegotiation> negotiate(
    PeerConnection connection,
    Map<String, dynamic> parameters,
  ) async {
    // Simple negotiation - in practice this would be more sophisticated
    final peerCapabilities = await connection.getCapabilities();
    final commonCapabilities = capabilities.intersection(peerCapabilities);

    return ProtocolNegotiation(
      success: commonCapabilities.isNotEmpty,
      agreedVersion: version,
      capabilities: commonCapabilities,
      parameters: parameters,
    );
  }

  @override
  Future<SyncSession> startSync(
    PeerConnection connection,
    Set<CID> roots, {
    Map<String, dynamic>? options,
  }) async {
    final request = SyncRequest(roots: roots, options: options ?? {});
    await connection.sendMessage(request);

    return BitSwapSyncSession(
      peer: connection.peer,
      protocol: this,
      connection: connection,
    );
  }

  @override
  Future<SyncSession> handleSyncRequest(
    PeerConnection connection,
    SyncRequest request,
  ) async {
    // Accept all requests in this simple implementation
    final response = SyncResponse(
      accepted: true,
      sessionId: _generateSessionId(),
    );

    await connection.sendMessage(response);

    return BitSwapSyncSession(
      peer: connection.peer,
      protocol: this,
      connection: connection,
    );
  }

  @override
  ProtocolMessage decodeMessage(Uint8List data) {
    // Simple decoding - in practice this would be more sophisticated
    throw UnimplementedError('Message decoding not implemented');
  }

  @override
  Uint8List encodeMessage(ProtocolMessage message) {
    return message.toBytes();
  }

  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp % 1000000;
    return 'session-$timestamp-$random';
  }
}

/// BitSwap synchronization session implementation.
class BitSwapSyncSession implements SyncSession {
  /// Creates a BitSwap sync session.
  BitSwapSyncSession({
    required this.peer,
    required this.protocol,
    required PeerConnection connection,
  }) : _connection = connection,
       _state = SessionState.initializing,
       _events = StreamController<SessionEvent>.broadcast(),
       _stats = SessionStats.empty();

  @override
  final Peer peer;

  @override
  final SyncProtocol protocol;

  final PeerConnection _connection;
  SessionState _state;
  final StreamController<SessionEvent> _events;
  SessionStats _stats;

  @override
  SessionState get state => _state;

  @override
  Stream<SessionEvent> get events => _events.stream;

  @override
  SessionStats get stats => _stats;

  @override
  Future<void> requestBlocks(Set<CID> cids) async {
    final message = BlockRequestMessage(cids: cids, priority: 1);
    await _connection.sendMessage(message);

    _events.add(BlocksRequested(cids: cids, timestamp: DateTime.now()));

    _stats = SessionStats(
      blocksRequested: _stats.blocksRequested + cids.length,
      blocksReceived: _stats.blocksReceived,
      blocksSent: _stats.blocksSent,
      bytesReceived: _stats.bytesReceived,
      bytesSent: _stats.bytesSent,
      duration: _stats.duration,
      messagesExchanged: _stats.messagesExchanged + 1,
    );
  }

  @override
  Future<void> sendBlocks(Set<Block> blocks) async {
    final message = BlockDelivery(blocks: blocks);
    await _connection.sendMessage(message);

    _events.add(BlocksSent(blocks: blocks, timestamp: DateTime.now()));

    final bytesSent = blocks.fold(0, (sum, block) => sum + block.size);
    _stats = SessionStats(
      blocksRequested: _stats.blocksRequested,
      blocksReceived: _stats.blocksReceived,
      blocksSent: _stats.blocksSent + blocks.length,
      bytesReceived: _stats.bytesReceived,
      bytesSent: _stats.bytesSent + bytesSent,
      duration: _stats.duration,
      messagesExchanged: _stats.messagesExchanged + 1,
    );
  }

  @override
  Future<void> announceBlocks(Set<CID> cids) async {
    final message = BlockAnnouncement(cids: cids);
    await _connection.sendMessage(message);

    _stats = SessionStats(
      blocksRequested: _stats.blocksRequested,
      blocksReceived: _stats.blocksReceived,
      blocksSent: _stats.blocksSent,
      bytesReceived: _stats.bytesReceived,
      bytesSent: _stats.bytesSent,
      duration: _stats.duration,
      messagesExchanged: _stats.messagesExchanged + 1,
    );
  }

  @override
  Future<void> close() async {
    _setState(SessionState.completing);
    // Send close message, clean up resources, etc.
    _setState(SessionState.closed);
    await _events.close();
  }

  @override
  Future<void> abort([String? reason]) async {
    _setState(SessionState.aborted);
    // Send abort message, clean up resources, etc.
    await _events.close();
  }

  void _setState(SessionState newState) {
    final oldState = _state;
    _state = newState;
    _events.add(
      SessionStateChanged(
        oldState: oldState,
        newState: newState,
        timestamp: DateTime.now(),
      ),
    );
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

/// Exception thrown when protocol negotiation fails.
class NegotiationException extends ProtocolException {
  /// Creates a negotiation exception.
  const NegotiationException(String message, {super.cause}) : super(message);
}

/// Exception thrown when session operations fail.
class SessionException extends ProtocolException {
  /// Creates a session exception.
  const SessionException(String message, {super.cause}) : super(message);
}
