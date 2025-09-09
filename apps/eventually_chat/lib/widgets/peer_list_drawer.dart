import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_peer.dart';
import '../services/eventually_chat_service.dart';

class PeerListDrawer extends StatelessWidget {
  const PeerListDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.hub, color: Colors.white, size: 48),
                SizedBox(height: 16),
                Text(
                  'DAG Peers',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<EventuallyChatService>(
              builder: (context, chatService, child) {
                if (chatService.peers.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_find, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No peers connected',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'This demo simulates peer discovery. In a real implementation, peers would connect via network protocols.',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    // Summary stats
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Connected Peers',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              Text(
                                '${chatService.onlinePeerCount}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Known',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                              Text(
                                '${chatService.peerCount}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Peer list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: chatService.peers.length,
                        itemBuilder: (context, index) {
                          final peer = chatService.peers[index];
                          return PeerTile(peer: peer);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Current user info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Consumer<EventuallyChatService>(
              builder: (context, chatService, child) {
                return Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(chatService.userName ?? ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chatService.userName ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'You (DAG Node)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final words = name.trim().split(' ');
    if (words.length == 1) {
      return words[0].substring(0, 1).toUpperCase();
    }
    return '${words[0].substring(0, 1)}${words[1].substring(0, 1)}'
        .toUpperCase();
  }
}

class PeerTile extends StatelessWidget {
  final ChatPeer peer;

  const PeerTile({super.key, required this.peer});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _getStatusColor(),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            _getInitials(peer.name),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(
        peer.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_getStatusText()),
          if (peer.knownBlockCount > 0)
            Text(
              '${peer.knownBlockCount} blocks known',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _getStatusColor(),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 4),
          Icon(Icons.hub, size: 12, color: Colors.grey.shade500),
        ],
      ),
      dense: true,
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final words = name.trim().split(' ');
    if (words.length == 1) {
      return words[0].substring(0, 1).toUpperCase();
    }
    return '${words[0].substring(0, 1)}${words[1].substring(0, 1)}'
        .toUpperCase();
  }

  Color _getStatusColor() {
    if (!peer.isOnline) return Colors.grey;

    switch (peer.status) {
      case ChatPeerStatus.connecting:
        return Colors.orange;
      case ChatPeerStatus.connected:
        return Colors.green;
      case ChatPeerStatus.syncing:
        return Colors.blue;
      case ChatPeerStatus.disconnected:
        return Colors.grey;
      case ChatPeerStatus.failed:
        return Colors.red;
    }
  }

  String _getStatusText() {
    if (!peer.isOnline) {
      if (peer.lastSeen != null) {
        final now = DateTime.now();
        final difference = now.difference(peer.lastSeen!);
        if (difference.inMinutes < 1) {
          return 'Last seen just now';
        } else if (difference.inHours < 1) {
          return 'Last seen ${difference.inMinutes}m ago';
        } else if (difference.inDays < 1) {
          return 'Last seen ${difference.inHours}h ago';
        } else {
          return 'Last seen ${difference.inDays}d ago';
        }
      } else {
        return 'Offline';
      }
    }

    return '${peer.status.displayName} • DAG Peer';
  }
}
