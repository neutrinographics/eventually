import 'dart:async';
import 'package:meta/meta.dart';
import 'block.dart';
import 'cid.dart';
import 'dag.dart';
import 'store.dart';
import 'peer.dart';

/// Interface for synchronizing Merkle DAGs between peers.
///
/// The synchronizer manages the process of discovering missing blocks,
/// requesting them from peers, and keeping the local DAG up to date
/// with changes from the network.
abstract interface class Synchronizer {
  /// The local store containing blocks.
  Store get store;

  /// The local DAG representation.
  DAG get dag;

  /// The peer manager for network communication.
  PeerManager get peerManager;

  /// Stream of synchronization events.
  Stream<SyncEvent> get syncEvents;

  /// Synchronizes with a specific peer.
  ///
  /// Compares the local state with the peer's state and exchanges
  /// any missing blocks to achieve consistency.
  Future<SyncResult> syncWithPeer(Peer peer, {Set<CID>? roots});

  /// Synchronizes with all connected peers.
  ///
  /// Performs synchronization with each connected peer in parallel.
  Future<List<SyncResult>> syncWithAllPeers({Set<CID>? roots});

  /// Starts continuous synchronization in the background.
  ///
  /// The synchronizer will periodically check for updates from peers
  /// and sync any new content automatically.
  void startContinuousSync({Duration interval = const Duration(seconds: 30)});

  /// Stops continuous synchronization.
  void stopContinuousSync();

  /// Whether continuous synchronization is running.
  bool get isContinuousSyncRunning;

  /// Announces new blocks to peers.
  ///
  /// Notifies connected peers about newly added blocks so they can
  /// request them if needed.
  Future<void> announceBlocks(Set<CID> cids);

  /// Requests missing blocks for a specific DAG root.
  ///
  /// Walks the DAG from the given root and identifies any missing blocks,
  /// then requests them from available peers.
  Future<Set<Block>> fetchMissingBlocks(CID root);

  /// Gets synchronization statistics.
  Future<SyncStats> getStats();

  /// Closes the synchronizer and releases resources.
  Future<void> close();
}

/// Default implementation of the Synchronizer interface.
class DefaultSynchronizer implements Synchronizer {
  /// Creates a new synchronizer.
  DefaultSynchronizer({
    required Store store,
    required DAG dag,
    required PeerManager peerManager,
  }) : _store = store,
       _dag = dag,
       _peerManager = peerManager,
       _syncEvents = StreamController<SyncEvent>.broadcast(),
       _continuousSyncTimer = null,
       _stats = SyncStats.empty();

  final Store _store;
  final DAG _dag;
  final PeerManager _peerManager;
  final StreamController<SyncEvent> _syncEvents;
  Timer? _continuousSyncTimer;
  SyncStats _stats;

  @override
  Store get store => _store;

  @override
  DAG get dag => _dag;

  @override
  PeerManager get peerManager => _peerManager;

  @override
  Stream<SyncEvent> get syncEvents => _syncEvents.stream;

  @override
  bool get isContinuousSyncRunning => _continuousSyncTimer?.isActive == true;

  @override
  Future<SyncResult> syncWithPeer(Peer peer, {Set<CID>? roots}) async {
    final startTime = DateTime.now();
    final connection = await _peerManager.connect(peer);

    try {
      _syncEvents.add(SyncStarted(peer: peer, timestamp: startTime));

      // Get the roots to sync (default to all DAG roots if not specified)
      final syncRoots = roots ?? dag.rootBlocks.map((b) => b.cid).toSet();

      // Find what blocks we need
      final missingBlocks = <CID>{};
      for (final root in syncRoots) {
        final missing = await _findMissingBlocks(connection, root);
        missingBlocks.addAll(missing);
      }

      // Request missing blocks
      final fetchedBlocks = <Block>[];
      for (final cid in missingBlocks) {
        final block = await connection.requestBlock(cid);
        if (block != null) {
          await _store.put(block);
          _dag.addBlock(block);
          fetchedBlocks.add(block);
        }
      }

      // Send blocks that the peer is missing
      final sentBlocks = await _sendMissingBlocksToPeer(connection, syncRoots);

      final duration = DateTime.now().difference(startTime);
      final result = SyncResult(
        peer: peer,
        blocksReceived: fetchedBlocks.length,
        blocksSent: sentBlocks.length,
        bytesReceived: fetchedBlocks.fold(0, (sum, b) => sum + b.size),
        bytesSent: sentBlocks.fold(0, (sum, b) => sum + b.size),
        duration: duration,
        success: true,
      );

      _updateStats(result);
      _syncEvents.add(SyncCompleted(result: result, timestamp: DateTime.now()));

      return result;
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      final result = SyncResult(
        peer: peer,
        blocksReceived: 0,
        blocksSent: 0,
        bytesReceived: 0,
        bytesSent: 0,
        duration: duration,
        success: false,
        error: e.toString(),
      );

      _syncEvents.add(
        SyncFailed(peer: peer, error: e.toString(), timestamp: DateTime.now()),
      );

      return result;
    }
  }

  @override
  Future<List<SyncResult>> syncWithAllPeers({Set<CID>? roots}) async {
    final peers = peerManager.connectedPeers.toList();
    final futures = peers.map((peer) => syncWithPeer(peer, roots: roots));
    return await Future.wait(futures);
  }

  @override
  void startContinuousSync({Duration interval = const Duration(seconds: 30)}) {
    stopContinuousSync();

    _continuousSyncTimer = Timer.periodic(interval, (_) async {
      try {
        await syncWithAllPeers();
      } catch (e) {
        _syncEvents.add(
          SyncFailed(
            peer: null,
            error: 'Continuous sync failed: $e',
            timestamp: DateTime.now(),
          ),
        );
      }
    });
  }

  @override
  void stopContinuousSync() {
    _continuousSyncTimer?.cancel();
    _continuousSyncTimer = null;
  }

  @override
  Future<void> announceBlocks(Set<CID> cids) async {
    if (cids.isEmpty) return;

    final message = Have(cids: cids);
    await _peerManager.broadcast(message);
  }

  @override
  Future<Set<Block>> fetchMissingBlocks(CID root) async {
    final missing = <CID>{};
    final visited = <String>{};

    // Find all missing blocks in the DAG
    await _walkDAG(root, (cid) async {
      if (visited.contains(cid.toString())) return true;
      visited.add(cid.toString());

      if (!await _store.has(cid)) {
        missing.add(cid);
        return false; // Don't traverse further if block is missing
      }
      return true;
    });

    // Request missing blocks from peers
    final fetchedBlocks = <Block>{};

    for (final cid in missing) {
      for (final peer in _peerManager.connectedPeers) {
        try {
          final connection = await _peerManager.connect(peer);
          final block = await connection.requestBlock(cid);

          if (block != null && block.validate()) {
            await _store.put(block);
            _dag.addBlock(block);
            fetchedBlocks.add(block);
            break; // Found the block, move to next
          }
        } catch (e) {
          // Try next peer
          continue;
        }
      }
    }

    return fetchedBlocks;
  }

  @override
  Future<SyncStats> getStats() async {
    return _stats;
  }

  @override
  Future<void> close() async {
    stopContinuousSync();
    await _syncEvents.close();
  }

  // Private helper methods

  Future<Set<CID>> _findMissingBlocks(
    PeerConnection connection,
    CID root,
  ) async {
    final missing = <CID>{};
    final visited = <String>{};

    await _walkDAG(root, (cid) async {
      if (visited.contains(cid.toString())) return true;
      visited.add(cid.toString());

      if (!await _store.has(cid)) {
        // Check if peer has this block
        if (await connection.hasBlock(cid)) {
          missing.add(cid);
        }
        return false;
      }
      return true;
    });

    return missing;
  }

  Future<List<Block>> _sendMissingBlocksToPeer(
    PeerConnection connection,
    Set<CID> roots,
  ) async {
    final sentBlocks = <Block>[];

    // This is a simplified implementation
    // In practice, you'd want to negotiate what the peer needs

    return sentBlocks;
  }

  Future<void> _walkDAG(CID root, Future<bool> Function(CID) visitor) async {
    final stack = <CID>[root];

    while (stack.isNotEmpty) {
      final cid = stack.removeLast();

      if (!await visitor(cid)) continue;

      // Get the block and add its links to the stack
      final block = await _store.get(cid);
      if (block != null) {
        final links = block.extractLinks();
        stack.addAll(links);
      }
    }
  }

  void _updateStats(SyncResult result) {
    _stats = SyncStats(
      totalSyncs: _stats.totalSyncs + 1,
      successfulSyncs: _stats.successfulSyncs + (result.success ? 1 : 0),
      totalBlocksReceived: _stats.totalBlocksReceived + result.blocksReceived,
      totalBlocksSent: _stats.totalBlocksSent + result.blocksSent,
      totalBytesReceived: _stats.totalBytesReceived + result.bytesReceived,
      totalBytesSent: _stats.totalBytesSent + result.bytesSent,
      lastSyncTime: DateTime.now(),
    );
  }
}

/// Result of a synchronization operation.
@immutable
class SyncResult {
  /// Creates a sync result.
  const SyncResult({
    required this.peer,
    required this.blocksReceived,
    required this.blocksSent,
    required this.bytesReceived,
    required this.bytesSent,
    required this.duration,
    required this.success,
    this.error,
  });

  /// The peer that was synchronized with.
  final Peer peer;

  /// Number of blocks received from the peer.
  final int blocksReceived;

  /// Number of blocks sent to the peer.
  final int blocksSent;

  /// Number of bytes received.
  final int bytesReceived;

  /// Number of bytes sent.
  final int bytesSent;

  /// Duration of the synchronization.
  final Duration duration;

  /// Whether the synchronization was successful.
  final bool success;

  /// Error message if the synchronization failed.
  final String? error;

  @override
  String toString() =>
      'SyncResult('
      'peer: ${peer.id}, '
      'received: $blocksReceived blocks ($bytesReceived bytes), '
      'sent: $blocksSent blocks ($bytesSent bytes), '
      'duration: ${duration.inMilliseconds}ms, '
      'success: $success'
      ')';
}

/// Statistics about synchronization operations.
@immutable
class SyncStats {
  /// Creates sync statistics.
  const SyncStats({
    required this.totalSyncs,
    required this.successfulSyncs,
    required this.totalBlocksReceived,
    required this.totalBlocksSent,
    required this.totalBytesReceived,
    required this.totalBytesSent,
    this.lastSyncTime,
  });

  /// Total number of sync operations performed.
  final int totalSyncs;

  /// Number of successful sync operations.
  final int successfulSyncs;

  /// Total blocks received across all syncs.
  final int totalBlocksReceived;

  /// Total blocks sent across all syncs.
  final int totalBlocksSent;

  /// Total bytes received across all syncs.
  final int totalBytesReceived;

  /// Total bytes sent across all syncs.
  final int totalBytesSent;

  /// Timestamp of the last sync operation.
  final DateTime? lastSyncTime;

  /// Creates empty statistics.
  factory SyncStats.empty() {
    return const SyncStats(
      totalSyncs: 0,
      successfulSyncs: 0,
      totalBlocksReceived: 0,
      totalBlocksSent: 0,
      totalBytesReceived: 0,
      totalBytesSent: 0,
    );
  }

  /// Success rate as a percentage.
  double get successRate => totalSyncs > 0 ? successfulSyncs / totalSyncs : 0.0;

  @override
  String toString() =>
      'SyncStats('
      'syncs: $successfulSyncs/$totalSyncs (${(successRate * 100).toStringAsFixed(1)}%), '
      'blocks: ${totalBlocksReceived + totalBlocksSent}, '
      'bytes: ${totalBytesReceived + totalBytesSent}'
      ')';
}

/// Base class for synchronization events.
@immutable
sealed class SyncEvent {
  /// Creates a sync event.
  const SyncEvent({required this.timestamp});

  /// When this event occurred.
  final DateTime timestamp;
}

/// Event when synchronization starts.
@immutable
final class SyncStarted extends SyncEvent {
  /// Creates a sync started event.
  const SyncStarted({required this.peer, required super.timestamp});

  /// The peer being synchronized with.
  final Peer peer;
}

/// Event when synchronization completes successfully.
@immutable
final class SyncCompleted extends SyncEvent {
  /// Creates a sync completed event.
  const SyncCompleted({required this.result, required super.timestamp});

  /// The result of the synchronization.
  final SyncResult result;
}

/// Event when synchronization fails.
@immutable
final class SyncFailed extends SyncEvent {
  /// Creates a sync failed event.
  const SyncFailed({
    required this.peer,
    required this.error,
    required super.timestamp,
  });

  /// The peer that the sync failed with (null for general failures).
  final Peer? peer;

  /// The error that caused the failure.
  final String error;
}

/// Event when new blocks are discovered during sync.
@immutable
final class BlocksDiscovered extends SyncEvent {
  /// Creates a blocks discovered event.
  const BlocksDiscovered({
    required this.blocks,
    required this.peer,
    required super.timestamp,
  });

  /// The blocks that were discovered.
  final Set<CID> blocks;

  /// The peer that provided the blocks.
  final Peer peer;
}

/// Event when blocks are successfully fetched.
@immutable
final class BlocksFetched extends SyncEvent {
  /// Creates a blocks fetched event.
  const BlocksFetched({
    required this.blocks,
    required this.peer,
    required super.timestamp,
  });

  /// The blocks that were fetched.
  final Set<Block> blocks;

  /// The peer that provided the blocks.
  final Peer peer;
}

/// Exception thrown when synchronization operations fail.
class SyncException implements Exception {
  /// Creates a sync exception.
  const SyncException(this.message, {this.peer, this.cause});

  /// The error message.
  final String message;

  /// The peer involved in the failed operation, if any.
  final Peer? peer;

  /// The underlying cause of the error.
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('SyncException: $message');
    if (peer != null) {
      buffer.write(' (peer: ${peer!.id})');
    }
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}

/// Exception thrown when a required block cannot be found.
class BlockNotFoundException extends SyncException {
  /// Creates a block not found exception.
  const BlockNotFoundException(CID cid, {super.peer})
    : super('Block not found: $cid');

  /// The CID that could not be found.
  CID get cid => CID.parse(message.split(': ')[1]);
}

/// Exception thrown when synchronization times out.
class SyncTimeoutException extends SyncException {
  /// Creates a sync timeout exception.
  const SyncTimeoutException(String message, {super.peer}) : super(message);
}
