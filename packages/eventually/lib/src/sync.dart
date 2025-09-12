import 'dart:async';
import 'package:meta/meta.dart';
import 'block.dart';
import 'cid.dart';
import 'dag.dart';
import 'store.dart';
import 'peer.dart';
import 'transport.dart';
import 'peer_config.dart';
import 'generic_peer_manager.dart';

/// Interface for synchronizing Merkle DAGs between peers.
///
/// The synchronizer manages the process of discovering missing blocks,
/// requesting them from peers, and keeping the local DAG up to date
/// with changes from the network.
/// TODO: remove this interface, and just have a single implementation.
abstract interface class Synchronizer {
  /// The local store containing blocks.
  Store get store;

  /// The local DAG representation.
  DAG get dag;

  /// The peer manager for network communication.
  PeerManager get peerManager;

  /// Stream of synchronization events.
  Stream<SyncEvent> get syncEvents;

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

  /// Gets peer statistics.
  Future<PeerStats> getPeerStats();

  /// Connects to a peer by ID.
  Future<void> connectToPeer(PeerId peerId);

  /// Stream of peer connection events.
  Stream<PeerEvent> get peerEvents;

  /// All currently connected peers.
  Iterable<Peer> get connectedPeers;

  /// Initializes the synchronizer and starts orchestration.
  Future<void> start();

  /// Closes the synchronizer and releases resources.
  Future<void> stop();
}

/// Default implementation of the Synchronizer interface.
///
/// This synchronizer fully manages both the transport layer and peer manager
/// internally. The application only needs to provide the transport and config,
/// and the synchronizer handles all peer discovery, connection management,
/// and synchronization operations.
class DefaultSynchronizer implements Synchronizer {
  /// Creates a new synchronizer.
  ///
  /// The synchronizer will create and fully manage the peer manager internally.
  /// The application should not interact with the peer manager directly.
  ///
  /// Example:
  /// ```dart
  /// final synchronizer = DefaultSynchronizer(
  ///   store: _store,
  ///   dag: _dag,
  ///   transport: transport,
  ///   config: config,
  /// );
  /// await synchronizer.initialize();
  /// ```
  DefaultSynchronizer({
    required Store store,
    required DAG dag,
    required Transport transport,
    required PeerConfig config,
    PeerManager? peerManager,
  }) : _store = store,
       _dag = dag,
       _transport = transport,
       _config = config,
       _peerManager = peerManager ?? GenericPeerManager(config: config),
       _syncEvents = StreamController<SyncEvent>.broadcast(),
       _continuousSyncTimer = null,
       _discoveryTimer = null,
       _stats = SyncStats.empty(),
       _isStarted = false;

  final Store _store;
  final DAG _dag;
  final Transport _transport;
  final PeerConfig _config;
  final PeerManager _peerManager;
  final StreamController<SyncEvent> _syncEvents;
  Timer? _continuousSyncTimer;
  Timer? _discoveryTimer;
  SyncStats _stats;
  bool _isStarted;
  StreamSubscription<IncomingBytes>? _incomingBytesSubscription;

  @override
  Store get store => _store;

  @override
  DAG get dag => _dag;

  @override
  PeerManager get peerManager => _peerManager;

  @override
  Stream<SyncEvent> get syncEvents => _syncEvents.stream;

  @override
  Future<PeerStats> getPeerStats() async {
    return await _peerManager.getStats();
  }

  @override
  Stream<PeerEvent> get peerEvents => _peerManager.peerEvents;

  @override
  Iterable<Peer> get connectedPeers => _peerManager.connectedPeers;

  @override
  Future<void> start() async {
    if (_isStarted) return;

    await _transport.initialize();
    _setupIncomingMessageHandlers();
    _startSyncTimer();
    _startPeerDiscoveryTimer();

    _isStarted = true;
  }

  void _setupIncomingMessageHandlers() {
    _incomingBytesSubscription = _transport.incomingBytes.listen(
      _peerManager.handleIncomingBytes,
      onError: _handleTransportError,
    );

    _peerManager.outgoingBytes.listen(
      _transport.sendBytes,
      onError: _handleTransportError,
    );
  }

  void _startPeerDiscoveryTimer() {
    if (_config.discoveryInterval <= Duration.zero) return;

    _discoveryTimer = Timer.periodic(_config.discoveryInterval, (_) async {
      await _discoverPeers();
    });
  }

  /// Orchestrates peer discovery: transport finds peers, peer manager handles them
  Future<void> _discoverPeers() async {
    if (!_isStarted) return;

    try {
      final discoveredDevices = await _transport.discoverDevices();

      for (final device in discoveredDevices) {
        // TODO: catch connection failures so we don't prevent other devices from connecting.
        final peer = await _peerManager.registerDeviceAsPeer(
          device,
          timeout: _config.handshakeTimeout,
        );
        if (_config.autoConnect &&
            _peerManager.connectedPeers.length < _config.maxConnections) {
          await _peerManager.connectToPeer(peer.id);
        }
      }
    } catch (e) {
      _syncEvents.add(
        SyncFailed(
          peer: null,
          error: 'Peer discovery failed: $e',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  void _handleTransportError(dynamic error) {
    _syncEvents.add(
      SyncFailed(
        peer: null,
        error: 'Transport error: $error',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> connectToPeer(PeerId peerId) async {
    if (!_isStarted) {
      throw SyncException('Synchronizer not started');
    }
    await _peerManager.connectToPeer(peerId);
  }

  Future<SyncResult> _syncWithPeer(Peer peer, {Set<CID>? roots}) async {
    final startTime = DateTime.now();

    if (!peer.isActive) {
      throw SyncException('Peer not connected: ${peer.id}');
    }

    try {
      _syncEvents.add(SyncStarted(peer: peer, timestamp: startTime));

      // Get the roots to sync (default to all DAG roots if not specified)
      final syncRoots = roots ?? dag.rootBlocks.map((b) => b.cid).toSet();

      // Find what blocks we need
      final missingBlocks = <CID>{};
      for (final root in syncRoots) {
        final missing = await _findMissingBlocks(peer, root);
        missingBlocks.addAll(missing);
      }

      // Request missing blocks
      final fetchedBlocks = <Block>[];
      for (final cid in missingBlocks) {
        try {
          final block = await _requestBlockFromPeer(peer, cid);
          if (block != null) {
            await _store.put(block);
            _dag.addBlock(block);
            fetchedBlocks.add(block);
          }
        } catch (e) {
          // Continue with other blocks if one fails
          continue;
        }
      }

      // Send blocks that the peer is missing
      final sentBlocks = await _sendMissingBlocksToPeer(peer, syncRoots);

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

  Future<void> _syncWithPeers() async {
    // TODO: Implement syncing with connected peers
    throw UnimplementedError('Sync with peers is not implemented');
  }

  void _startSyncTimer() {
    _stopContinuousSync();

    _continuousSyncTimer = Timer.periodic(_config.syncInterval, (_) async {
      try {
        await _syncWithPeers();
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

  void _stopContinuousSync() {
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
          final connection = _peerManager.getConnection(peer.id);
          if (connection == null) continue;

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
  Future<void> stop() async {
    if (!_isStarted) return;

    // Stop timers
    _continuousSyncTimer?.cancel();
    _continuousSyncTimer = null;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    // Cancel stream subscriptions
    await _incomingBytesSubscription?.cancel();
    _incomingBytesSubscription = null;

    // Disconnect all peers
    await _peerManager.disconnectAll();

    // Dispose of peer manager
    await _peerManager.dispose();

    // Shutdown transport
    await _transport.shutdown();

    await _syncEvents.close();
    _isStarted = false;
  }

  // Private helper methods

  Future<Block?> _requestBlockFromPeer(Peer peer, CID cid) async {
    // Send Want message to peer requesting the block
    final wantMessage = Want(cids: {cid});
    await _peerManager.broadcast(wantMessage); // For now, broadcast to all

    // In a full implementation, this would:
    // 1. Send Want message specifically to this peer
    // 2. Wait for Block response with timeout
    // 3. Return the received block

    // For now, return null (block not available)
    return null;
  }

  Future<Set<CID>> _findMissingBlocks(Peer peer, CID root) async {
    final missing = <CID>{};
    final visited = <String>{};

    await _walkDAG(root, (cid) async {
      if (visited.contains(cid.toString())) return true;
      visited.add(cid.toString());

      if (!await _store.has(cid)) {
        // Assume peer might have this block
        // In a full implementation, we'd check peer's advertised blocks
        missing.add(cid);
        return false;
      }
      return true;
    });

    return missing;
  }

  Future<List<Block>> _sendMissingBlocksToPeer(
    Peer peer,
    Set<CID> roots,
  ) async {
    final sentBlocks = <Block>[];

    // This is a simplified implementation
    // In practice, you'd want to:
    // 1. Check what blocks the peer is missing (via Want messages)
    // 2. Send Have messages for blocks we have
    // 3. Send Block messages when peer requests them

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
