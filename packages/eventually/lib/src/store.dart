import 'package:meta/meta.dart';
import 'block.dart';
import 'cid.dart';

/// Interface for storing and retrieving blocks in a content-addressed system.
///
/// The store provides persistent storage for blocks, allowing them to be
/// retrieved by their CID. Implementations can vary from in-memory storage
/// to distributed storage systems.
abstract interface class Store {
  /// Stores a block in the store.
  ///
  /// If a block with the same CID already exists, it may be overwritten
  /// depending on the implementation. Returns true if the block was stored
  /// successfully, false otherwise.
  Future<bool> put(Block block);

  /// Stores multiple blocks in the store.
  ///
  /// This is more efficient than calling [put] multiple times as it allows
  /// the implementation to batch operations. Returns a map indicating
  /// which blocks were stored successfully.
  Future<Map<CID, bool>> putAll(Iterable<Block> blocks);

  /// Retrieves a block by its CID.
  ///
  /// Returns null if the block is not found in the store.
  Future<Block?> get(CID cid);

  /// Retrieves multiple blocks by their CIDs.
  ///
  /// Returns a map from CID to Block. Missing blocks will not be included
  /// in the result map.
  Future<Map<CID, Block>> getAll(Iterable<CID> cids);

  /// Checks if a block exists in the store.
  ///
  /// This is potentially more efficient than calling [get] if you only
  /// need to check existence.
  Future<bool> has(CID cid);

  /// Checks which blocks exist in the store.
  ///
  /// Returns a map from CID to boolean indicating existence.
  Future<Map<CID, bool>> hasAll(Iterable<CID> cids);

  /// Removes a block from the store.
  ///
  /// Returns true if the block was removed, false if it didn't exist.
  Future<bool> delete(CID cid);

  /// Removes multiple blocks from the store.
  ///
  /// Returns a map indicating which blocks were successfully removed.
  Future<Map<CID, bool>> deleteAll(Iterable<CID> cids);

  /// Gets the size of a block without retrieving its data.
  ///
  /// Returns null if the block doesn't exist.
  Future<int?> getSize(CID cid);

  /// Lists all CIDs in the store.
  ///
  /// This operation may be expensive for large stores and should be used
  /// with caution in production systems.
  Stream<CID> listCids();

  /// Gets statistics about the store.
  Future<StoreStats> getStats();

  /// Performs garbage collection to remove unreferenced blocks.
  ///
  /// Takes a set of root CIDs that should be kept. All blocks reachable
  /// from these roots will be preserved, while unreferenced blocks may
  /// be removed.
  Future<GCResult> collectGarbage(Set<CID> roots);

  /// Closes the store and releases any resources.
  ///
  /// After calling this method, the store should not be used.
  Future<void> close();
}

/// Statistics about a store's contents and performance.
@immutable
class StoreStats {
  /// Creates store statistics.
  const StoreStats({
    required this.totalBlocks,
    required this.totalSize,
    required this.averageBlockSize,
    this.metadata = const {},
  });

  /// Total number of blocks stored.
  final int totalBlocks;

  /// Total size of all blocks in bytes.
  final int totalSize;

  /// Average size of blocks in bytes.
  final double averageBlockSize;

  /// Additional implementation-specific metadata.
  final Map<String, dynamic> metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreStats &&
          runtimeType == other.runtimeType &&
          totalBlocks == other.totalBlocks &&
          totalSize == other.totalSize &&
          averageBlockSize == other.averageBlockSize &&
          metadata == other.metadata;

  @override
  int get hashCode =>
      Object.hash(totalBlocks, totalSize, averageBlockSize, metadata);

  @override
  String toString() =>
      'StoreStats('
      'blocks: $totalBlocks, '
      'size: $totalSize bytes, '
      'avgSize: ${averageBlockSize.toStringAsFixed(1)} bytes'
      ')';
}

/// Result of a garbage collection operation.
@immutable
class GCResult {
  /// Creates a garbage collection result.
  const GCResult({
    required this.blocksRemoved,
    required this.bytesFreed,
    required this.duration,
    this.details = const {},
  });

  /// Number of blocks that were removed.
  final int blocksRemoved;

  /// Number of bytes that were freed.
  final int bytesFreed;

  /// Duration of the garbage collection operation.
  final Duration duration;

  /// Additional details about the operation.
  final Map<String, dynamic> details;

  @override
  String toString() =>
      'GCResult('
      'removed: $blocksRemoved blocks, '
      'freed: $bytesFreed bytes, '
      'duration: ${duration.inMilliseconds}ms'
      ')';
}

/// In-memory implementation of Store for testing and development.
///
/// This implementation stores all blocks in memory and provides no persistence.
/// It should only be used for testing, development, or scenarios where
/// persistence is not required.
class MemoryStore implements Store {
  /// Creates a new in-memory store.
  MemoryStore() : _blocks = <String, Block>{}, _closed = false;

  final Map<String, Block> _blocks;
  bool _closed;

  void _checkClosed() {
    if (_closed) {
      throw StateError('Store has been closed');
    }
  }

  @override
  Future<bool> put(Block block) async {
    _checkClosed();

    // Validate the block before storing
    if (!block.validate()) {
      return false;
    }

    _blocks[block.cid.toString()] = block;
    return true;
  }

  @override
  Future<Map<CID, bool>> putAll(Iterable<Block> blocks) async {
    _checkClosed();

    final results = <CID, bool>{};

    for (final block in blocks) {
      results[block.cid] = await put(block);
    }

    return results;
  }

  @override
  Future<Block?> get(CID cid) async {
    _checkClosed();
    return _blocks[cid.toString()];
  }

  @override
  Future<Map<CID, Block>> getAll(Iterable<CID> cids) async {
    _checkClosed();

    final results = <CID, Block>{};

    for (final cid in cids) {
      final block = _blocks[cid.toString()];
      if (block != null) {
        results[cid] = block;
      }
    }

    return results;
  }

  @override
  Future<bool> has(CID cid) async {
    _checkClosed();
    return _blocks.containsKey(cid.toString());
  }

  @override
  Future<Map<CID, bool>> hasAll(Iterable<CID> cids) async {
    _checkClosed();

    final results = <CID, bool>{};

    for (final cid in cids) {
      results[cid] = _blocks.containsKey(cid.toString());
    }

    return results;
  }

  @override
  Future<bool> delete(CID cid) async {
    _checkClosed();
    return _blocks.remove(cid.toString()) != null;
  }

  @override
  Future<Map<CID, bool>> deleteAll(Iterable<CID> cids) async {
    _checkClosed();

    final results = <CID, bool>{};

    for (final cid in cids) {
      results[cid] = await delete(cid);
    }

    return results;
  }

  @override
  Future<int?> getSize(CID cid) async {
    _checkClosed();
    final block = _blocks[cid.toString()];
    return block?.size;
  }

  @override
  Stream<CID> listCids() async* {
    _checkClosed();

    for (final cidString in _blocks.keys) {
      yield CID.parse(cidString);
    }
  }

  @override
  Future<StoreStats> getStats() async {
    _checkClosed();

    final totalBlocks = _blocks.length;
    final totalSize = _blocks.values.fold(0, (sum, block) => sum + block.size);
    final averageBlockSize = totalBlocks > 0 ? totalSize / totalBlocks : 0.0;

    return StoreStats(
      totalBlocks: totalBlocks,
      totalSize: totalSize,
      averageBlockSize: averageBlockSize,
      metadata: {
        'implementation': 'MemoryStore',
        'maxBlockSize': _blocks.values.fold(
          0,
          (max, block) => block.size > max ? block.size : max,
        ),
        'minBlockSize': _blocks.isEmpty
            ? 0
            : _blocks.values.fold(
                _blocks.values.first.size,
                (min, block) => block.size < min ? block.size : min,
              ),
      },
    );
  }

  @override
  Future<GCResult> collectGarbage(Set<CID> roots) async {
    _checkClosed();

    final startTime = DateTime.now();
    final reachable = <String>{};

    // Find all reachable blocks using BFS
    final queue = <String>[];
    for (final root in roots) {
      queue.add(root.toString());
    }

    while (queue.isNotEmpty) {
      final cidString = queue.removeAt(0);
      if (reachable.contains(cidString)) continue;

      reachable.add(cidString);
      final block = _blocks[cidString];

      if (block != null) {
        // Add linked blocks to the queue
        final links = block.extractLinks();
        for (final link in links) {
          queue.add(link.toString());
        }
      }
    }

    // Remove unreachable blocks
    final toRemove = <String>[];
    int bytesFreed = 0;

    for (final entry in _blocks.entries) {
      if (!reachable.contains(entry.key)) {
        toRemove.add(entry.key);
        bytesFreed += entry.value.size;
      }
    }

    for (final cidString in toRemove) {
      _blocks.remove(cidString);
    }

    final duration = DateTime.now().difference(startTime);

    return GCResult(
      blocksRemoved: toRemove.length,
      bytesFreed: bytesFreed,
      duration: duration,
      details: {
        'totalBlocks': _blocks.length + toRemove.length,
        'reachableBlocks': reachable.length,
        'rootCount': roots.length,
      },
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    _blocks.clear();
  }

  /// Gets the number of blocks currently stored.
  int get length => _blocks.length;

  /// Whether the store is empty.
  bool get isEmpty => _blocks.isEmpty;

  /// Whether the store contains blocks.
  bool get isNotEmpty => _blocks.isNotEmpty;

  /// Clears all blocks from the store.
  ///
  /// This method is useful for testing scenarios where you need to reset
  /// the store to a clean state.
  void clear() {
    _checkClosed();
    _blocks.clear();
  }
}

/// Exception thrown when store operations fail.
class StoreException implements Exception {
  /// Creates a store exception.
  const StoreException(this.message, {this.cause});

  /// The error message.
  final String message;

  /// The underlying cause of the error, if any.
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'StoreException: $message (caused by: $cause)';
    }
    return 'StoreException: $message';
  }
}

/// Exception thrown when a block is not found in the store.
class BlockNotFoundException extends StoreException {
  /// Creates a block not found exception.
  const BlockNotFoundException(CID cid) : super('Block not found: $cid');

  /// The CID of the block that was not found.
  CID get cid => CID.parse(message.split(': ')[1]);
}

/// Exception thrown when a block fails validation.
class BlockValidationException extends StoreException {
  /// Creates a block validation exception.
  const BlockValidationException(CID cid, String reason)
    : super('Block validation failed for $cid: $reason');
}

/// A store decorator that adds caching capabilities.
class CachedStore implements Store {
  /// Creates a cached store that wraps another store.
  CachedStore(this._backend, {int maxCacheSize = 1000})
    : _cache = <String, Block>{},
      _maxCacheSize = maxCacheSize,
      _accessOrder = <String>[];

  final Store _backend;
  final Map<String, Block> _cache;
  final int _maxCacheSize;
  final List<String> _accessOrder;

  void _updateCache(String cidString, Block block) {
    // Remove from current position if exists
    _accessOrder.remove(cidString);

    // Add to front (most recently used)
    _accessOrder.insert(0, cidString);
    _cache[cidString] = block;

    // Evict least recently used if over capacity
    while (_cache.length > _maxCacheSize && _accessOrder.isNotEmpty) {
      final lru = _accessOrder.removeLast();
      _cache.remove(lru);
    }
  }

  void _markAccessed(String cidString) {
    if (_cache.containsKey(cidString)) {
      _accessOrder.remove(cidString);
      _accessOrder.insert(0, cidString);
    }
  }

  @override
  Future<bool> put(Block block) async {
    final result = await _backend.put(block);
    if (result) {
      _updateCache(block.cid.toString(), block);
    }
    return result;
  }

  @override
  Future<Map<CID, bool>> putAll(Iterable<Block> blocks) async {
    final results = await _backend.putAll(blocks);

    for (final block in blocks) {
      if (results[block.cid] == true) {
        _updateCache(block.cid.toString(), block);
      }
    }

    return results;
  }

  @override
  Future<Block?> get(CID cid) async {
    final cidString = cid.toString();

    // Check cache first
    if (_cache.containsKey(cidString)) {
      _markAccessed(cidString);
      return _cache[cidString];
    }

    // Fetch from backend
    final block = await _backend.get(cid);
    if (block != null) {
      _updateCache(cidString, block);
    }

    return block;
  }

  @override
  Future<Map<CID, Block>> getAll(Iterable<CID> cids) async {
    final results = <CID, Block>{};
    final toFetch = <CID>[];

    // Check cache for each CID
    for (final cid in cids) {
      final cidString = cid.toString();
      if (_cache.containsKey(cidString)) {
        _markAccessed(cidString);
        results[cid] = _cache[cidString]!;
      } else {
        toFetch.add(cid);
      }
    }

    // Fetch remaining from backend
    if (toFetch.isNotEmpty) {
      final backendResults = await _backend.getAll(toFetch);
      results.addAll(backendResults);

      // Update cache
      for (final entry in backendResults.entries) {
        _updateCache(entry.key.toString(), entry.value);
      }
    }

    return results;
  }

  @override
  Future<bool> has(CID cid) async {
    final cidString = cid.toString();

    if (_cache.containsKey(cidString)) {
      return true;
    }

    return await _backend.has(cid);
  }

  @override
  Future<Map<CID, bool>> hasAll(Iterable<CID> cids) => _backend.hasAll(cids);

  @override
  Future<bool> delete(CID cid) async {
    final result = await _backend.delete(cid);
    if (result) {
      final cidString = cid.toString();
      _cache.remove(cidString);
      _accessOrder.remove(cidString);
    }
    return result;
  }

  @override
  Future<Map<CID, bool>> deleteAll(Iterable<CID> cids) async {
    final results = await _backend.deleteAll(cids);

    for (final entry in results.entries) {
      if (entry.value) {
        final cidString = entry.key.toString();
        _cache.remove(cidString);
        _accessOrder.remove(cidString);
      }
    }

    return results;
  }

  @override
  Future<int?> getSize(CID cid) async {
    final cidString = cid.toString();

    // Check cache first
    if (_cache.containsKey(cidString)) {
      return _cache[cidString]!.size;
    }

    return await _backend.getSize(cid);
  }

  @override
  Stream<CID> listCids() => _backend.listCids();

  @override
  Future<StoreStats> getStats() => _backend.getStats();

  @override
  Future<GCResult> collectGarbage(Set<CID> roots) async {
    final result = await _backend.collectGarbage(roots);

    // Clear cache of removed blocks
    final reachable = <String>{};
    // This is a simplified approach - in practice you'd want to be more precise
    _cache.clear();
    _accessOrder.clear();

    return result;
  }

  @override
  Future<void> close() async {
    _cache.clear();
    _accessOrder.clear();
    await _backend.close();
  }
}
