import 'dart:async';
import 'package:meta/meta.dart';
import 'package:transport/transport.dart';
import 'block.dart';
import 'cid.dart';
import 'dag.dart';
import 'store.dart';
import 'peer.dart';

/// Configuration for the Eventually synchronizer.
@immutable
class SyncConfig {
  const SyncConfig({
    this.announceNewBlocks = true,
    this.autoRequestMissing = true,
    this.maxConcurrentRequests = 10,
  });

  /// Whether to automatically announce new blocks to peers.
  final bool announceNewBlocks;

  /// Whether to automatically request missing blocks when discovered.
  final bool autoRequestMissing;

  /// Maximum number of concurrent block requests.
  final int maxConcurrentRequests;
}

/// Synchronizer for Merkle DAG content using the transport library.
///
/// This synchronizer focuses purely on content synchronization logic,
/// using the transport library for all peer management and networking.
class EventuallySynchronizer {
  /// Creates a new synchronizer.
  EventuallySynchronizer({
    required Store store,
    required DAG dag,
    SyncConfig? config,
  }) : _store = store,
       _dag = dag,
       _config = config ?? const SyncConfig(),
       _syncEvents = StreamController<SyncEvent>.broadcast(),
       _stats = SyncStats.empty();

  final Store _store;
  final DAG _dag;
  final SyncConfig _config;
  final StreamController<SyncEvent> _syncEvents;
  SyncStats _stats;

  TransportManager? _transport;
  StreamSubscription<TransportMessage>? _messageSubscription;

  /// Stream of synchronization events.
  Stream<SyncEvent> get syncEvents => _syncEvents.stream;

  /// Current synchronization statistics.
  SyncStats get stats => _stats;

  /// Initializes the synchronizer with a transport manager.
  Future<void> initialize(TransportManager transport) async {
    _transport = transport;

    // Listen for incoming messages and handle sync protocol messages
    _messageSubscription = transport.messagesReceived.listen(
      _handleIncomingMessage,
      onError: _handleTransportError,
    );
  }

  /// Announces new blocks to all connected peers.
  Future<void> announceBlocks(Set<CID> cids) async {
    if (cids.isEmpty || _transport == null) return;

    final haveMessage = Have(cids: cids);
    await _broadcastMessage(haveMessage);

    _syncEvents.add(BlocksAnnounced(cids: cids, timestamp: DateTime.now()));
  }

  /// Requests missing blocks for a DAG root.
  Future<Set<Block>> fetchMissingBlocks(CID root) async {
    final missing = <CID>{};
    final visited = <String>{};

    // Find missing blocks by walking the DAG
    await _walkDAG(root, (cid) async {
      final cidString = cid.toString();
      if (visited.contains(cidString)) return true;
      visited.add(cidString);

      if (!await _store.has(cid)) {
        missing.add(cid);
        return false; // Don't traverse further if block is missing
      }
      return true;
    });

    if (missing.isEmpty) return {};

    // Request missing blocks from peers
    final wantMessage = Want(cids: missing);
    await _broadcastMessage(wantMessage);

    _syncEvents.add(BlocksRequested(cids: missing, timestamp: DateTime.now()));

    // In a real implementation, this would wait for responses
    // For now, return empty set
    return {};
  }

  /// Adds a block to the local store and DAG.
  Future<void> addBlock(Block block) async {
    await _store.put(block);
    _dag.addBlock(block);

    if (_config.announceNewBlocks) {
      await announceBlocks({block.cid});
    }
  }

  /// Disposes of the synchronizer and releases resources.
  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _syncEvents.close();
    _transport = null;
  }

  // Private helper methods

  Future<void> _handleIncomingMessage(TransportMessage message) async {
    try {
      final syncMessage = SyncMessageCodec.decode(message.data);
      if (syncMessage == null) return;

      switch (syncMessage) {
        case Want want:
          await _handleWantMessage(message.senderId, want);
          break;
        case Have have:
          await _handleHaveMessage(message.senderId, have);
          break;
        case BlockRequest request:
          await _handleBlockRequest(message.senderId, request);
          break;
        case BlockResponse response:
          await _handleBlockResponse(message.senderId, response);
          break;
      }
    } catch (e) {
      _syncEvents.add(
        SyncError(
          error: 'Failed to handle message from ${message.senderId.value}: $e',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _handleWantMessage(PeerId senderId, Want want) async {
    // Peer is requesting blocks - send any we have
    final blocksToSend = <Block>[];

    for (final cid in want.cids) {
      final block = await _store.get(cid);
      if (block != null) {
        blocksToSend.add(block);
      }
    }

    // Send blocks to the requesting peer
    for (final block in blocksToSend) {
      final response = BlockResponse(block: block);
      await _sendMessage(senderId, response);
    }

    if (blocksToSend.isNotEmpty) {
      _updateStats(blocksSent: blocksToSend.length);
    }
  }

  Future<void> _handleHaveMessage(PeerId senderId, Have have) async {
    if (!_config.autoRequestMissing) return;

    // Check which blocks we need
    final needed = <CID>{};
    for (final cid in have.cids) {
      if (!await _store.has(cid)) {
        needed.add(cid);
      }
    }

    if (needed.isNotEmpty) {
      final request = Want(cids: needed);
      await _sendMessage(senderId, request);
    }
  }

  Future<void> _handleBlockRequest(
    PeerId senderId,
    BlockRequest request,
  ) async {
    final block = await _store.get(request.cid);
    if (block != null) {
      final response = BlockResponse(block: block);
      await _sendMessage(senderId, response);
      _updateStats(blocksSent: 1);
    }
  }

  Future<void> _handleBlockResponse(
    PeerId senderId,
    BlockResponse response,
  ) async {
    final block = response.block;

    // Validate and store the block
    if (block.validate()) {
      await _store.put(block);
      _dag.addBlock(block);

      _updateStats(blocksReceived: 1);

      _syncEvents.add(
        BlockReceived(
          cid: block.cid,
          fromPeer: senderId,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  Future<void> _broadcastMessage(SyncMessage message) async {
    final transport = _transport;
    if (transport == null) return;

    // Broadcast to all connected peers
    for (final peer in transport.peers.where(
      (p) => p.status == PeerStatus.connected,
    )) {
      await _sendMessage(peer.id, message);
    }
  }

  Future<void> _sendMessage(PeerId recipientId, SyncMessage message) async {
    final transport = _transport;
    if (transport == null) return;

    final transportMessage = TransportMessage(
      senderId: transport.localPeerId,
      recipientId: recipientId,
      data: message.toBytes(),
      timestamp: DateTime.now(),
    );

    await transport.sendMessage(transportMessage);
  }

  Future<void> _walkDAG(CID root, Future<bool> Function(CID) visitor) async {
    final stack = <CID>[root];
    final visited = <String>{};

    while (stack.isNotEmpty) {
      final cid = stack.removeLast();
      final cidString = cid.toString();

      if (visited.contains(cidString)) continue;
      visited.add(cidString);

      if (!await visitor(cid)) continue;

      // Get the block and add its links to the stack
      final block = await _store.get(cid);
      if (block != null) {
        final links = block.extractLinks();
        stack.addAll(links);
      }
    }
  }

  void _handleTransportError(dynamic error) {
    _syncEvents.add(
      SyncError(error: 'Transport error: $error', timestamp: DateTime.now()),
    );
  }

  void _updateStats({int blocksReceived = 0, int blocksSent = 0}) {
    _stats = SyncStats(
      totalBlocksReceived: _stats.totalBlocksReceived + blocksReceived,
      totalBlocksSent: _stats.totalBlocksSent + blocksSent,
      lastSyncTime: DateTime.now(),
    );
  }
}

/// Statistics about synchronization operations.
@immutable
class SyncStats {
  const SyncStats({
    required this.totalBlocksReceived,
    required this.totalBlocksSent,
    this.lastSyncTime,
  });

  final int totalBlocksReceived;
  final int totalBlocksSent;
  final DateTime? lastSyncTime;

  factory SyncStats.empty() {
    return const SyncStats(totalBlocksReceived: 0, totalBlocksSent: 0);
  }

  @override
  String toString() =>
      'SyncStats('
      'received: $totalBlocksReceived, '
      'sent: $totalBlocksSent'
      ')';
}

/// Base class for synchronization events.
@immutable
sealed class SyncEvent {
  const SyncEvent({required this.timestamp});
  final DateTime timestamp;
}

/// Event when blocks are announced to peers.
@immutable
final class BlocksAnnounced extends SyncEvent {
  const BlocksAnnounced({required this.cids, required super.timestamp});
  final Set<CID> cids;
}

/// Event when blocks are requested from peers.
@immutable
final class BlocksRequested extends SyncEvent {
  const BlocksRequested({required this.cids, required super.timestamp});
  final Set<CID> cids;
}

/// Event when a block is received from a peer.
@immutable
final class BlockReceived extends SyncEvent {
  const BlockReceived({
    required this.cid,
    required this.fromPeer,
    required super.timestamp,
  });

  final CID cid;
  final PeerId fromPeer;
}

/// Event when a sync error occurs.
@immutable
final class SyncError extends SyncEvent {
  const SyncError({required this.error, required super.timestamp});
  final String error;
}

/// Exception thrown when synchronization operations fail.
class SyncException implements Exception {
  const SyncException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'SyncException: $message (caused by: $cause)';
    }
    return 'SyncException: $message';
  }
}
