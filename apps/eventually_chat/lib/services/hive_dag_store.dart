import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' hide debugPrint;
import 'package:eventually/eventually.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Hive-based implementation of Store for persisting blocks to disk.
///
/// This store provides persistent storage for blocks in the Merkle DAG,
/// allowing the chat application to maintain message history across
/// app restarts and device reboots.
class HiveDAGStore implements Store {
  static const String _blocksBoxName = 'eventually_blocks';
  static const String _metadataBoxName = 'eventually_metadata';

  LazyBox<Uint8List>? _blocksBox;
  Box<Map<dynamic, dynamic>>? _metadataBox;
  bool _isInitialized = false;
  bool _isClosed = false;

  /// Initializes the Hive store.
  ///
  /// Creates necessary Hive boxes for storing blocks and metadata.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize Hive
      if (!Hive.isAdapterRegistered(0)) {
        await Hive.initFlutter();
      }

      // Get app documents directory for Hive storage
      Directory appDocDir;
      if (!kIsWeb) {
        appDocDir = await getApplicationDocumentsDirectory();
        final hivePath = '${appDocDir.path}/hive_eventually';

        // Create directory if it doesn't exist
        final dir = Directory(hivePath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        Hive.init(hivePath);
      }

      // Open the blocks box (lazy for better memory usage with large data)
      _blocksBox = await Hive.openLazyBox<Uint8List>(_blocksBoxName);

      // Open metadata box for additional information
      _metadataBox = await Hive.openBox<Map<dynamic, dynamic>>(
        _metadataBoxName,
      );

      _isInitialized = true;
      debugPrint('✅ HiveDAGStore initialized successfully');
    } catch (e) {
      throw Exception('Failed to initialize Hive DAG store: $e');
    }
  }

  void _checkInitialized() {
    if (!_isInitialized) {
      throw StateError('Store not initialized. Call initialize() first.');
    }
    if (_isClosed) {
      throw StateError('Store has been closed');
    }
  }

  @override
  Future<bool> put(Block block) async {
    _checkInitialized();

    try {
      // Validate block before storing
      if (!block.validate()) {
        return false;
      }

      final cidString = block.cid.toString();
      await _blocksBox!.put(cidString, block.data);

      // Store metadata
      final metadata = {
        'cid': cidString,
        'size': block.size,
        'codec': block.cid.codec,
        'hashAlgorithm': block.cid.hashAlgorithm,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      await _metadataBox!.put(cidString, metadata);

      debugPrint(
        '💾 Stored block ${cidString.substring(0, 16)}... (${block.size} bytes)',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Failed to put block ${block.cid}: $e');
      return false;
    }
  }

  @override
  Future<Map<CID, bool>> putAll(Iterable<Block> blocks) async {
    final results = <CID, bool>{};
    for (final block in blocks) {
      results[block.cid] = await put(block);
    }
    return results;
  }

  @override
  Future<Block?> get(CID cid) async {
    _checkInitialized();

    try {
      final cidString = cid.toString();
      final data = await _blocksBox!.get(cidString);

      if (data == null) {
        return null;
      }

      return Block.withCid(cid, data);
    } catch (e) {
      debugPrint('❌ Failed to get block $cid: $e');
      return null;
    }
  }

  @override
  Future<Map<CID, Block>> getAll(Iterable<CID> cids) async {
    final results = <CID, Block>{};
    for (final cid in cids) {
      final block = await get(cid);
      if (block != null) {
        results[cid] = block;
      }
    }
    return results;
  }

  @override
  Future<bool> has(CID cid) async {
    _checkInitialized();

    try {
      final cidString = cid.toString();
      return _blocksBox!.containsKey(cidString);
    } catch (e) {
      debugPrint('❌ Failed to check if block $cid exists: $e');
      return false;
    }
  }

  @override
  Future<Map<CID, bool>> hasAll(Iterable<CID> cids) async {
    final results = <CID, bool>{};
    for (final cid in cids) {
      results[cid] = await has(cid);
    }
    return results;
  }

  @override
  Future<bool> delete(CID cid) async {
    _checkInitialized();

    try {
      final cidString = cid.toString();
      final hadBlock = await has(cid);
      await _blocksBox!.delete(cidString);
      await _metadataBox!.delete(cidString);
      if (hadBlock) {
        debugPrint('🗑️ Deleted block ${cidString.substring(0, 16)}...');
      }
      return hadBlock;
    } catch (e) {
      debugPrint('❌ Failed to delete block $cid: $e');
      return false;
    }
  }

  @override
  Future<Map<CID, bool>> deleteAll(Iterable<CID> cids) async {
    final results = <CID, bool>{};
    for (final cid in cids) {
      results[cid] = await delete(cid);
    }
    return results;
  }

  @override
  Future<int?> getSize(CID cid) async {
    _checkInitialized();

    try {
      final cidString = cid.toString();
      final metadata = _metadataBox!.get(cidString);
      if (metadata != null) {
        final metadataMap = Map<String, dynamic>.from(metadata);
        return metadataMap['size'] as int?;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Failed to get size for block $cid: $e');
      return null;
    }
  }

  @override
  Stream<CID> listCids() async* {
    _checkInitialized();

    for (final key in _blocksBox!.keys) {
      try {
        yield CID.parse(key.toString());
      } catch (e) {
        debugPrint('❌ Failed to parse CID from key: $key');
      }
    }
  }

  @override
  Future<StoreStats> getStats() async {
    _checkInitialized();

    try {
      final blockCount = await getBlockCount();
      final totalSize = await getTotalSize();
      final averageBlockSize = blockCount > 0 ? totalSize / blockCount : 0.0;

      final codecCounts = <int, int>{};
      for (final metadata in _metadataBox!.values) {
        final metadataMap = Map<String, dynamic>.from(metadata);
        final codec = metadataMap['codec'] as int? ?? 0;
        codecCounts[codec] = (codecCounts[codec] ?? 0) + 1;
      }

      return StoreStats(
        totalBlocks: blockCount,
        totalSize: totalSize,
        averageBlockSize: averageBlockSize,
        metadata: {
          'storageBackend': 'Hive',
          'codecDistribution': codecCounts,
          'isInitialized': _isInitialized,
          'isClosed': _isClosed,
          'boxPath': _blocksBox?.path,
        },
      );
    } catch (e) {
      throw StoreException('Failed to get storage stats: $e');
    }
  }

  @override
  Future<GCResult> collectGarbage(Set<CID> roots) async {
    _checkInitialized();

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
      final data = await _blocksBox!.get(cidString);

      if (data != null) {
        try {
          final cid = CID.parse(cidString);
          final block = Block.withCid(cid, data);
          final links = block.extractLinks();
          for (final link in links) {
            queue.add(link.toString());
          }
        } catch (e) {
          debugPrint('❌ Error processing block $cidString during GC: $e');
        }
      }
    }

    // Remove unreachable blocks
    final toRemove = <String>[];
    int bytesFreed = 0;

    for (final key in _blocksBox!.keys) {
      final keyString = key.toString();
      if (!reachable.contains(keyString)) {
        toRemove.add(keyString);
        final metadata = _metadataBox!.get(keyString);
        if (metadata != null) {
          final metadataMap = Map<String, dynamic>.from(metadata);
          bytesFreed += metadataMap['size'] as int? ?? 0;
        }
      }
    }

    for (final cidString in toRemove) {
      await _blocksBox!.delete(cidString);
      await _metadataBox!.delete(cidString);
    }

    final duration = DateTime.now().difference(startTime);
    debugPrint(
      '🧹 GC removed ${toRemove.length} blocks, freed $bytesFreed bytes',
    );

    return GCResult(
      blocksRemoved: toRemove.length,
      bytesFreed: bytesFreed,
      duration: duration,
      details: {'reachableBlocks': reachable.length, 'rootCount': roots.length},
    );
  }

  /// Gets all CIDs stored in the DAG store.
  /// Note: This is not part of the Store interface but useful for debugging.
  Future<List<CID>> getAllCids() async {
    _checkInitialized();

    try {
      final cids = <CID>[];
      await for (final cid in listCids()) {
        cids.add(cid);
      }
      return cids;
    } catch (e) {
      throw StoreException('Failed to get all CIDs: $e');
    }
  }

  /// Gets all blocks stored in the DAG store.
  Future<List<Block>> getAllBlocks() async {
    _checkInitialized();

    try {
      final blocks = <Block>[];
      for (final key in _blocksBox!.keys) {
        try {
          final cid = CID.parse(key.toString());
          final data = await _blocksBox!.get(key);
          if (data != null) {
            blocks.add(Block.withCid(cid, data));
          }
        } catch (e) {
          debugPrint('❌ Failed to load block with key: $key');
        }
      }
      return blocks;
    } catch (e) {
      throw Exception('Failed to get all blocks: $e');
    }
  }

  /// Gets the number of blocks stored.
  Future<int> getBlockCount() async {
    _checkInitialized();
    return _blocksBox!.length;
  }

  /// Gets the total size of all stored blocks in bytes.
  Future<int> getTotalSize() async {
    _checkInitialized();

    try {
      int totalSize = 0;
      for (final metadata in _metadataBox!.values) {
        final metadataMap = Map<String, dynamic>.from(metadata);
        totalSize += metadataMap['size'] as int? ?? 0;
      }
      return totalSize;
    } catch (e) {
      throw Exception('Failed to calculate total size: $e');
    }
  }

  /// Gets blocks by codec type.
  Future<List<Block>> getBlocksByCodec(int codec) async {
    _checkInitialized();

    try {
      final blocks = <Block>[];
      for (final key in _metadataBox!.keys) {
        final metadata = _metadataBox!.get(key);
        if (metadata != null) {
          final metadataMap = Map<String, dynamic>.from(metadata);
          if (metadataMap['codec'] == codec) {
            final cidString = key.toString();
            try {
              final cid = CID.parse(cidString);
              final data = await _blocksBox!.get(cidString);
              if (data != null) {
                blocks.add(Block.withCid(cid, data));
              }
            } catch (e) {
              debugPrint('❌ Failed to load block: $cidString');
            }
          }
        }
      }
      return blocks;
    } catch (e) {
      throw Exception('Failed to get blocks by codec $codec: $e');
    }
  }

  /// Gets detailed storage statistics.
  /// Note: This returns more detailed stats than the Store interface getStats().
  Future<Map<String, dynamic>> getDetailedStats() async {
    final storeStats = await getStats();
    return {
      'blockCount': storeStats.totalBlocks,
      'totalSize': storeStats.totalSize,
      'averageBlockSize': storeStats.averageBlockSize,
      ...storeStats.metadata,
    };
  }

  /// Compacts the Hive boxes to reclaim storage space.
  Future<void> compact() async {
    _checkInitialized();

    try {
      await _blocksBox!.compact();
      await _metadataBox!.compact();
      debugPrint('📦 Compacted Hive DAG store');
    } catch (e) {
      throw StoreException('Failed to compact store: $e');
    }
  }

  /// Clears all blocks from the store.
  Future<void> clear() async {
    _checkInitialized();

    try {
      await _blocksBox!.clear();
      await _metadataBox!.clear();
      debugPrint('🧹 Cleared all blocks from DAG store');
    } catch (e) {
      throw StoreException('Failed to clear store: $e');
    }
  }

  /// Validates the integrity of all stored blocks.
  Future<Map<String, dynamic>> validateAll() async {
    _checkInitialized();

    try {
      int validBlocks = 0;
      int invalidBlocks = 0;
      final invalidCids = <String>[];

      for (final key in _blocksBox!.keys) {
        try {
          final cid = CID.parse(key.toString());
          final data = await _blocksBox!.get(key);

          if (data != null) {
            final block = Block.withCid(cid, data);
            if (block.validate()) {
              validBlocks++;
            } else {
              invalidBlocks++;
              invalidCids.add(cid.toString());
            }
          }
        } catch (e) {
          invalidBlocks++;
          invalidCids.add(key.toString());
        }
      }

      return {
        'totalBlocks': validBlocks + invalidBlocks,
        'validBlocks': validBlocks,
        'invalidBlocks': invalidBlocks,
        'invalidCids': invalidCids,
        'integrityOk': invalidBlocks == 0,
      };
    } catch (e) {
      throw StoreException('Failed to validate blocks: $e');
    }
  }

  @override
  Future<void> close() async {
    if (!_isInitialized || _isClosed) return;

    try {
      await _blocksBox?.close();
      await _metadataBox?.close();
      _isClosed = true;
      _isInitialized = false;
      debugPrint('🔒 HiveDAGStore closed successfully');
    } catch (e) {
      throw StoreException('Failed to close DAG store: $e');
    }
  }
}
