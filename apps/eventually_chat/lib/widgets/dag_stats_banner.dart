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

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, child) {
        return FutureBuilder<Map<String, dynamic>>(
          future: chatService.getDAGStats(),
          builder: (context, snapshot) {
            final dagStats = snapshot.data ?? {};
            final stats = chatService.getConnectionStats();

            return GestureDetector(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
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
                              'Received',
                              '${stats['blocksReceived'] ?? 0}',
                              Icons.download,
                            ),
                          ),
                          Expanded(
                            child: _buildStatColumn(
                              'Sent',
                              '${stats['blocksSent'] ?? 0}',
                              Icons.upload,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Last sync info
                      if (stats['lastSyncTime'] != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 12,
                                color: Colors.green.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Last sync: ${_formatTime(stats['lastSyncTime'])}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

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

  String _formatTime(String? isoTime) {
    if (isoTime == null) return 'Never';
    try {
      final dateTime = DateTime.parse(isoTime);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}
