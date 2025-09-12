import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:eventually/src/transport.dart';
import 'package:meta/meta.dart';
import 'peer.dart';
import 'block.dart';
import 'cid.dart';

/// Handles the initial handshake protocol to discover peer identity
/// after a transport connection is established.
///
/// This bridges the transport and application layers by negotiating
/// the peer's application-layer identity over the transport connection.
abstract interface class PeerHandshake {
  /// Performs the handshake protocol as the initiator.
  ///
  /// Takes a raw transport connection and negotiates the peer identity.
  /// Returns the discovered peer and an established peer connection.
  Future<PeerHandshakeResult> initiate(
    TransportConnection transport,
    PeerId localPeerId,
  );

  /// Handles an incoming handshake as the responder.
  ///
  /// Responds to handshake requests from other peers and establishes
  /// the peer connection after identity exchange.
  Future<PeerHandshakeResult> respond(
    TransportConnection transport,
    PeerId localPeerId,
  );

  /// Gets the timeout duration for handshake operations.
  Duration get handshakeTimeout;
}

/// Result of a successful peer handshake.
@immutable
class PeerHandshakeResult {
  const PeerHandshakeResult({required this.peer, required this.connection});

  /// The discovered peer identity.
  final Peer peer;

  /// The established peer connection.
  final PeerConnection connection;
}

/// Default implementation of the peer handshake protocol.
class DefaultPeerHandshake implements PeerHandshake {
  const DefaultPeerHandshake({
    this.handshakeTimeout = const Duration(seconds: 30),
  });

  @override
  final Duration handshakeTimeout;

  @override
  Future<PeerHandshakeResult> initiate(
    TransportConnection transport,
    PeerId localPeerId,
  ) async {
    final completer = Completer<PeerHandshakeResult>();
    late StreamSubscription subscription;

    // Set up timeout
    final timer = Timer(handshakeTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          PeerHandshakeException(
            'Handshake timeout',
            endpoint: transport.endpoint,
          ),
        );
      }
    });

    try {
      // Listen for handshake response
      subscription = transport.dataStream.listen((data) {
        try {
          final message = _parseHandshakeMessage(data);
          if (message.type == HandshakeMessageType.response) {
            // Create transport peer from transport connection
            final transportPeer = TransportPeer(
              address: TransportPeerAddress(transport.endpoint.address),
              displayName:
                  message.metadata['displayName']?.toString() ??
                  message.peerId.value,
              protocol: transport.endpoint.protocol,
              metadata: transport.endpoint.metadata,
            );

            // Create peer and connection
            final peer = Peer(
              id: message.peerId,
              transportPeer: transportPeer,
              metadata: message.metadata,
            );
            final connection = TransportPeerConnection(
              peer: peer,
              transport: transport,
            );

            if (!completer.isCompleted) {
              completer.complete(
                PeerHandshakeResult(peer: peer, connection: connection),
              );
            }
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(
              PeerHandshakeException(
                'Failed to parse handshake response: $e',
                endpoint: transport.endpoint,
              ),
            );
          }
        }
      });

      // Send handshake request
      final request = HandshakeMessage(
        type: HandshakeMessageType.request,
        peerId: localPeerId,
        metadata: const {},
      );
      await transport.sendData(request.toBytes());

      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  @override
  Future<PeerHandshakeResult> respond(
    TransportConnection transport,
    PeerId localPeerId,
  ) async {
    final completer = Completer<PeerHandshakeResult>();
    late StreamSubscription subscription;

    // Set up timeout
    final timer = Timer(handshakeTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          PeerHandshakeException(
            'Handshake timeout',
            endpoint: transport.endpoint,
          ),
        );
      }
    });

    try {
      // Listen for handshake request
      subscription = transport.dataStream.listen((data) async {
        try {
          final message = _parseHandshakeMessage(data);
          if (message.type == HandshakeMessageType.request) {
            // Send handshake response
            final response = HandshakeMessage(
              type: HandshakeMessageType.response,
              peerId: localPeerId,
              metadata: const {},
            );
            await transport.sendData(response.toBytes());

            // Create transport peer from transport connection
            final transportPeer = TransportPeer(
              address: TransportPeerAddress(transport.endpoint.address),
              displayName:
                  message.metadata['displayName']?.toString() ??
                  message.peerId.value,
              protocol: transport.endpoint.protocol,
              metadata: transport.endpoint.metadata,
            );

            // Create peer and connection
            final peer = Peer(
              id: message.peerId,
              transportPeer: transportPeer,
              metadata: message.metadata,
            );
            final connection = TransportPeerConnection(
              peer: peer,
              transport: transport,
            );

            if (!completer.isCompleted) {
              completer.complete(
                PeerHandshakeResult(peer: peer, connection: connection),
              );
            }
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(
              PeerHandshakeException(
                'Failed to handle handshake request: $e',
                endpoint: transport.endpoint,
              ),
            );
          }
        }
      });

      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  HandshakeMessage _parseHandshakeMessage(List<int> data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      return HandshakeMessage.fromJson(json);
    } catch (e) {
      throw PeerHandshakeException('Invalid handshake message format: $e');
    }
  }
}

/// Message exchanged during peer handshake.
@immutable
class HandshakeMessage {
  const HandshakeMessage({
    required this.type,
    required this.peerId,
    required this.metadata,
  });

  final HandshakeMessageType type;
  final PeerId peerId;
  final Map<String, dynamic> metadata;

  /// Converts the message to bytes for transmission.
  List<int> toBytes() {
    final json = {'type': type.name, 'peer_id': peerId, 'metadata': metadata};
    return utf8.encode(jsonEncode(json));
  }

  /// Creates a message from received bytes.
  factory HandshakeMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = HandshakeMessageType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => throw ArgumentError('Unknown handshake type: $typeStr'),
    );

    return HandshakeMessage(
      type: type,
      peerId: PeerId(json['peer_id'] as String),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HandshakeMessage &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          peerId == other.peerId &&
          metadata == other.metadata;

  @override
  int get hashCode => Object.hash(type, peerId, metadata);

  @override
  String toString() => 'HandshakeMessage(type: $type, peerId: $peerId)';
}

/// Types of handshake messages.
enum HandshakeMessageType { request, response }

/// A peer connection that wraps a transport connection.
class TransportPeerConnection implements PeerConnection {
  TransportPeerConnection({
    required Peer peer,
    required TransportConnection transport,
  }) : _peer = peer,
       transport = transport {
    _initializeMessageStream();
  }

  final Peer _peer;
  final TransportConnection transport;
  final StreamController<Message> _messagesController =
      StreamController<Message>.broadcast();

  StreamSubscription? _transportSubscription;
  bool _isDisposed = false;

  @override
  Peer? get peer => _peer;

  @override
  bool get isConnected => transport.isConnected && !_isDisposed;

  @override
  Stream<Message> get messages => _messagesController.stream;

  void _initializeMessageStream() {
    _transportSubscription = transport.dataStream.listen(
      (data) {
        try {
          // Skip handshake messages - they're handled separately
          if (_isHandshakeMessage(data)) return;

          final message = Message.fromBytes(Uint8List.fromList(data));
          _messagesController.add(message);
        } catch (e) {
          // Log error but don't break the stream
          // TODO: Add proper logging
        }
      },
      onError: (error) {
        _messagesController.addError(error);
      },
      onDone: () {
        _messagesController.close();
      },
    );
  }

  bool _isHandshakeMessage(List<int> data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      return json.containsKey('type') &&
          json.containsKey('peer_id') &&
          (json['type'] == 'request' || json['type'] == 'response');
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> connect() async {
    // Transport connection should already be established
    if (!transport.isConnected) {
      throw ConnectionException('Transport not connected', peerId: _peer.id);
    }
  }

  @override
  Future<void> disconnect() async {
    _isDisposed = true;
    await _transportSubscription?.cancel();
    await _messagesController.close();
    await transport.disconnect();
  }

  @override
  Future<void> sendMessage(dynamic message) async {
    if (!isConnected) {
      throw ConnectionException('Not connected to peer', peerId: _peer.id);
    }

    if (message is Message) {
      await transport.sendData(message.toBytes());
    } else {
      throw ArgumentError('Message must be of type Message');
    }
  }

  @override
  Future<Block?> requestBlock(CID cid) async {
    final request = BlockRequest(cid: cid);
    await sendMessage(request);

    // Wait for response (with timeout)
    final response = await messages
        .where((msg) => msg is BlockResponse)
        .cast<BlockResponse>()
        .where((resp) => resp.block.cid == cid)
        .timeout(const Duration(seconds: 30))
        .first;

    return response.block;
  }

  @override
  Future<List<Block>> requestBlocks(List<CID> cids) async {
    final blocks = <Block>[];
    for (final cid in cids) {
      final block = await requestBlock(cid);
      if (block != null) {
        blocks.add(block);
      }
    }
    return blocks;
  }

  @override
  Future<void> sendBlock(Block block) async {
    final response = BlockResponse(block: block);
    await sendMessage(response);
  }

  @override
  Future<bool> hasBlock(CID cid) async {
    // This would typically be implemented with a specific query message type
    // For now, just try to request it and see if we get a response
    try {
      final block = await requestBlock(cid);
      return block != null;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Set<String>> getCapabilities() async {
    // This would typically be exchanged during handshake
    // For now, return basic capabilities
    return {'blocks', 'sync'};
  }

  @override
  Future<Duration> ping() async {
    final start = DateTime.now();
    final ping = Ping();
    await sendMessage(ping);

    // Wait for pong
    await messages
        .where((msg) => msg is Pong)
        .timeout(const Duration(seconds: 10))
        .first;

    return DateTime.now().difference(start);
  }
}

/// Exception thrown when peer handshake fails.
class PeerHandshakeException implements Exception {
  const PeerHandshakeException(this.message, {this.endpoint, this.cause});

  final String message;
  final TransportEndpoint? endpoint;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('PeerHandshakeException: $message');
    if (endpoint != null) {
      buffer.write(' (endpoint: ${endpoint!.address})');
    }
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}
