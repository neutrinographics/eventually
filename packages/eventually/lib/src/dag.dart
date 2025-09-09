import 'dart:collection';
import 'package:meta/meta.dart';
import 'block.dart';
import 'cid.dart';

/// A Directed Acyclic Graph (DAG) implementation for content-addressed data.
///
/// The DAG provides a graph structure where nodes are blocks identified by CIDs,
/// and edges represent references between blocks. This forms the foundation
/// for distributed, versioned data structures.
class DAG {
  /// Creates a new empty DAG.
  DAG() : _blocks = <String, Block>{}, _links = <String, Set<String>>{};

  final Map<String, Block> _blocks;
  final Map<String, Set<String>> _links;

  /// Adds a block to the DAG.
  ///
  /// If the block already exists, it will be replaced. The method automatically
  /// discovers and registers links to other blocks based on the block's content.
  void addBlock(Block block) {
    final cidString = block.cid.toString();
    _blocks[cidString] = block;

    // Extract and register links
    final links = block.extractLinks();
    final linkSet = <String>{};

    for (final link in links) {
      linkSet.add(link.toString());
    }

    _links[cidString] = linkSet;
  }

  /// Gets a block by its CID.
  ///
  /// Returns null if the block is not found in the DAG.
  Block? getBlock(CID cid) {
    return _blocks[cid.toString()];
  }

  /// Checks if a block exists in the DAG.
  bool hasBlock(CID cid) {
    return _blocks.containsKey(cid.toString());
  }

  /// Removes a block from the DAG.
  ///
  /// Also removes any link information associated with the block.
  /// Returns true if the block was removed, false if it didn't exist.
  bool removeBlock(CID cid) {
    final cidString = cid.toString();
    final removed = _blocks.remove(cidString) != null;
    _links.remove(cidString);
    return removed;
  }

  /// Gets all blocks in the DAG.
  Iterable<Block> get blocks => _blocks.values;

  /// Gets all CIDs in the DAG.
  Iterable<CID> get cids => _blocks.keys.map((s) => CID.parse(s));

  /// Gets the number of blocks in the DAG.
  int get size => _blocks.length;

  /// Whether the DAG is empty.
  bool get isEmpty => _blocks.isEmpty;

  /// Whether the DAG contains blocks.
  bool get isNotEmpty => _blocks.isNotEmpty;

  /// Gets the direct children (linked blocks) of a block.
  ///
  /// Returns an empty iterable if the block doesn't exist or has no links.
  Iterable<CID> getChildren(CID cid) {
    final links = _links[cid.toString()];
    if (links == null) return const [];

    return links.map((s) => CID.parse(s));
  }

  /// Gets the direct parents (blocks that link to this block) of a block.
  Iterable<CID> getParents(CID cid) {
    final cidString = cid.toString();
    final parents = <String>[];

    for (final entry in _links.entries) {
      if (entry.value.contains(cidString)) {
        parents.add(entry.key);
      }
    }

    return parents.map((s) => CID.parse(s));
  }

  /// Performs a depth-first traversal starting from the given CID.
  ///
  /// The [visitor] function is called for each block in the traversal order.
  /// If [visitor] returns false, the traversal stops.
  void depthFirstTraversal(CID startCid, bool Function(Block block) visitor) {
    final visited = <String>{};
    final stack = <String>[startCid.toString()];

    while (stack.isNotEmpty) {
      final cidString = stack.removeLast();

      if (visited.contains(cidString)) continue;
      visited.add(cidString);

      final block = _blocks[cidString];
      if (block == null) continue;

      if (!visitor(block)) break;

      // Add children to stack (in reverse order for correct DFS order)
      final children = _links[cidString];
      if (children != null) {
        stack.addAll(children.toList().reversed);
      }
    }
  }

  /// Performs a breadth-first traversal starting from the given CID.
  ///
  /// The [visitor] function is called for each block in the traversal order.
  /// If [visitor] returns false, the traversal stops.
  void breadthFirstTraversal(CID startCid, bool Function(Block block) visitor) {
    final visited = <String>{};
    final queue = Queue<String>.from([startCid.toString()]);

    while (queue.isNotEmpty) {
      final cidString = queue.removeFirst();

      if (visited.contains(cidString)) continue;
      visited.add(cidString);

      final block = _blocks[cidString];
      if (block == null) continue;

      if (!visitor(block)) break;

      // Add children to queue
      final children = _links[cidString];
      if (children != null) {
        queue.addAll(children);
      }
    }
  }

  /// Gets all blocks reachable from the given CID.
  ///
  /// Returns a set of all blocks that can be reached by following links
  /// from the starting block.
  Set<Block> getReachableBlocks(CID startCid) {
    final reachable = <Block>{};

    depthFirstTraversal(startCid, (block) {
      reachable.add(block);
      return true;
    });

    return reachable;
  }

  /// Gets all CIDs reachable from the given CID.
  Set<CID> getReachableCids(CID startCid) {
    final reachable = <CID>{};

    depthFirstTraversal(startCid, (block) {
      reachable.add(block.cid);
      return true;
    });

    return reachable;
  }

  /// Checks if there's a path from one CID to another.
  bool hasPath(CID from, CID to) {
    final targetString = to.toString();
    bool found = false;

    depthFirstTraversal(from, (block) {
      if (block.cid.toString() == targetString) {
        found = true;
        return false; // Stop traversal
      }
      return true;
    });

    return found;
  }

  /// Finds the shortest path between two CIDs.
  ///
  /// Returns a list of CIDs representing the path from [from] to [to].
  /// Returns null if no path exists.
  List<CID>? findPath(CID from, CID to) {
    if (from == to) return [from];

    final targetString = to.toString();
    final visited = <String>{};
    final queue = Queue<List<String>>();

    queue.add([from.toString()]);

    while (queue.isNotEmpty) {
      final path = queue.removeFirst();
      final currentCidString = path.last;

      if (visited.contains(currentCidString)) continue;
      visited.add(currentCidString);

      if (currentCidString == targetString) {
        return path.map((s) => CID.parse(s)).toList();
      }

      final children = _links[currentCidString];
      if (children != null) {
        for (final child in children) {
          if (!visited.contains(child)) {
            queue.add([...path, child]);
          }
        }
      }
    }

    return null; // No path found
  }

  /// Detects cycles in the DAG.
  ///
  /// Returns true if any cycles are detected, false otherwise.
  /// Note: A properly formed DAG should never have cycles.
  bool hasCycles() {
    final visited = <String>{};
    final recursionStack = <String>{};

    bool dfsHasCycle(String cidString) {
      visited.add(cidString);
      recursionStack.add(cidString);

      final children = _links[cidString];
      if (children != null) {
        for (final child in children) {
          if (!visited.contains(child)) {
            if (dfsHasCycle(child)) return true;
          } else if (recursionStack.contains(child)) {
            return true; // Back edge found - cycle detected
          }
        }
      }

      recursionStack.remove(cidString);
      return false;
    }

    for (final cidString in _blocks.keys) {
      if (!visited.contains(cidString)) {
        if (dfsHasCycle(cidString)) return true;
      }
    }

    return false;
  }

  /// Gets the topological order of all blocks in the DAG.
  ///
  /// Returns a list of blocks in topological order, where each block
  /// appears before all blocks it links to.
  /// Throws [StateError] if the DAG contains cycles.
  List<Block> topologicalSort() {
    if (hasCycles()) {
      throw StateError('Cannot perform topological sort on cyclic graph');
    }

    final visited = <String>{};
    final stack = <String>[];

    void dfsVisit(String cidString) {
      visited.add(cidString);

      final children = _links[cidString];
      if (children != null) {
        for (final child in children) {
          if (!visited.contains(child)) {
            dfsVisit(child);
          }
        }
      }

      stack.add(cidString);
    }

    for (final cidString in _blocks.keys) {
      if (!visited.contains(cidString)) {
        dfsVisit(cidString);
      }
    }

    return stack.reversed.map((s) => _blocks[s]!).toList();
  }

  /// Gets root blocks (blocks with no parents).
  Iterable<Block> get rootBlocks {
    final allChildren = <String>{};
    for (final children in _links.values) {
      allChildren.addAll(children);
    }

    return _blocks.entries
        .where((entry) => !allChildren.contains(entry.key))
        .map((entry) => entry.value);
  }

  /// Gets leaf blocks (blocks with no children).
  Iterable<Block> get leafBlocks {
    return _blocks.entries
        .where((entry) => _links[entry.key]?.isEmpty != false)
        .map((entry) => entry.value);
  }

  /// Calculates statistics about the DAG structure.
  DAGStats calculateStats() {
    final roots = rootBlocks.length;
    final leaves = leafBlocks.length;
    final totalSize = _blocks.values.fold(0, (sum, block) => sum + block.size);

    int maxDepth = 0;
    int totalDepth = 0;
    int nodeCount = 0;

    for (final root in rootBlocks) {
      final depth = _calculateMaxDepth(root.cid.toString(), <String>{});
      maxDepth = depth > maxDepth ? depth : maxDepth;

      depthFirstTraversal(root.cid, (block) {
        totalDepth += _calculateDepth(block.cid.toString());
        nodeCount++;
        return true;
      });
    }

    final avgDepth = nodeCount > 0 ? totalDepth / nodeCount : 0.0;

    return DAGStats(
      totalBlocks: size,
      totalSize: totalSize,
      rootBlocks: roots,
      leafBlocks: leaves,
      maxDepth: maxDepth,
      averageDepth: avgDepth,
    );
  }

  int _calculateMaxDepth(String cidString, Set<String> visited) {
    if (visited.contains(cidString)) return 0;
    visited.add(cidString);

    final children = _links[cidString];
    if (children == null || children.isEmpty) return 1;

    int maxChildDepth = 0;
    for (final child in children) {
      final childDepth = _calculateMaxDepth(child, visited);
      maxChildDepth = childDepth > maxChildDepth ? childDepth : maxChildDepth;
    }

    return maxChildDepth + 1;
  }

  int _calculateDepth(String cidString) {
    // Calculate depth from any root
    for (final root in rootBlocks) {
      final path = findPath(root.cid, CID.parse(cidString));
      if (path != null) {
        return path.length - 1;
      }
    }
    return 0;
  }

  /// Merges another DAG into this one.
  ///
  /// All blocks from the other DAG are added to this DAG.
  /// Existing blocks are replaced if they have the same CID.
  void merge(DAG other) {
    for (final block in other.blocks) {
      addBlock(block);
    }
  }

  /// Creates a copy of this DAG.
  DAG copy() {
    final newDag = DAG();
    for (final block in blocks) {
      newDag.addBlock(block);
    }
    return newDag;
  }

  /// Clears all blocks from the DAG.
  void clear() {
    _blocks.clear();
    _links.clear();
  }

  @override
  String toString() {
    final stats = calculateStats();
    return 'DAG(blocks: ${stats.totalBlocks}, '
        'size: ${stats.totalSize} bytes, '
        'roots: ${stats.rootBlocks}, '
        'leaves: ${stats.leafBlocks})';
  }
}

/// Statistics about a DAG structure.
@immutable
class DAGStats {
  /// Creates DAG statistics.
  const DAGStats({
    required this.totalBlocks,
    required this.totalSize,
    required this.rootBlocks,
    required this.leafBlocks,
    required this.maxDepth,
    required this.averageDepth,
  });

  /// Total number of blocks in the DAG.
  final int totalBlocks;

  /// Total size of all blocks in bytes.
  final int totalSize;

  /// Number of root blocks (blocks with no parents).
  final int rootBlocks;

  /// Number of leaf blocks (blocks with no children).
  final int leafBlocks;

  /// Maximum depth of the DAG.
  final int maxDepth;

  /// Average depth of nodes in the DAG.
  final double averageDepth;

  @override
  String toString() =>
      'DAGStats('
      'blocks: $totalBlocks, '
      'size: $totalSize bytes, '
      'roots: $rootBlocks, '
      'leaves: $leafBlocks, '
      'maxDepth: $maxDepth, '
      'avgDepth: ${averageDepth.toStringAsFixed(2)}'
      ')';
}
