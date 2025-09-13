import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chat_service.dart';

/// A banner widget that shows DAG synchronization status and statistics.
///
/// This widget displays information about the Merkle DAG state, including
/// block count, peer connections, and sync status in a collapsible banner.
class DAGStatsBanner extends StatefulWidget {
  const DAGStatsBanner({super.key});

  @override
  State<DAGStatsBanner> createState() => _DAGStatsBannerState();
}

class _DAGStatsBannerState extends State<DAGStatsBanner> {
  bool _isExpanded = false;
  Map<String, dynamic>? _stats;
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (_isLoadingStats) return;

    setState(() {
      _isLoadingStats = true;
    });

    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      final stats = chatService.getConnectionStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stats = {};
          _isLoadingStats = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, child) {
        final stats = _stats ?? {};

        return FutureBuilder<Map<String, dynamic>>(
          future: chatService.getDAGStats(),
          builder: (context, snapshot) {
            final dagStats = snapshot.data ?? {};

            return GestureDetector(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
                if (_isExpanded) {
                  _loadStats();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                color: Colors.green.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.hub, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            chatService.hasConnectedPeers
                                ? 'DAG synchronized with ${chatService.onlinePeerCount} peer${chatService.onlinePeerCount != 1 ? 's' : ''}'
                                : 'DAG ready • Discovering peers...',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Icon(
                          _isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.green.shade700,
                        ),
                      ],
                    ),
                    if (_isExpanded) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      if (_isLoadingStats) ...[
                        const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ] else ...[
                        // DAG Statistics
                        Text(
                          'Merkle DAG Statistics',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatColumn(
                                'Blocks',
                                '${dagStats['total_blocks'] ?? 0}',
                                Icons.category,
                              ),
                            ),
                            Expanded(
                              child: _buildStatColumn(
                                'Size',
                                _formatBytes(dagStats['total_size'] ?? 0),
                                Icons.storage,
                              ),
                            ),
                            Expanded(
                              child: _buildStatColumn(
                                'Depth',
                                '${dagStats['max_depth'] ?? 0}',
                                Icons.account_tree,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Network Statistics
                        Text(
                          'Network Statistics',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatColumn(
                                'Online',
                                '${stats['onlinePeerCount'] ?? 0}',
                                Icons.people,
                              ),
                            ),
                            Expanded(
                              child: _buildStatColumn(
                                'Syncs',
                                '${stats['syncCount'] ?? 0}',
                                Icons.sync,
                              ),
                            ),
                            Expanded(
                              child: _buildStatColumn(
                                'Success',
                                '${((stats['syncSuccessRate'] ?? 0.0) * 100).toStringAsFixed(0)}%',
                                Icons.check_circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Tips
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.lightbulb_outline,
                                    size: 14,
                                    color: Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'How it works:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '• Messages are stored as content-addressed blocks\n• Blocks form a Merkle DAG for integrity verification\n• Peers automatically sync new blocks\n• Data is eventually consistent across all nodes',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.green.shade600),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade800,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.green.shade600),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
