import 'dart:async';

import 'package:eventually/eventually.dart';

import '../models/chat_message.dart';
import '../models/chat_peer.dart';

/// Common interface for both old and new chat service implementations.
///
/// This interface allows the UI to work with either the legacy
/// EventuallyChatService or the new ModernChatService without changes.
abstract class ChatServiceInterface {
  // Basic properties
  PeerId? get userId;
  String? get userName;
  bool get isInitialized;
  bool get isStarted;
  String? get error;

  // Chat data
  List<ChatMessage> get messages;
  Iterable<ChatPeer> get peers;
  Iterable<ChatPeer> get onlinePeers;

  // Statistics
  int get messageCount;
  int get peerCount;
  int get onlinePeerCount;
  bool get hasConnectedPeers;

  // Core operations
  Future<void> setUserName(String name);
  Future<void> initialize();
  Future<void> start();
  Future<void> stop();

  // Messaging
  Future<void> sendMessage(
    String content, {
    String? replyToCid,
    Map<String, dynamic>? metadata,
  });

  // Message queries
  ChatMessage? getMessageByCid(String cidString);
  List<ChatMessage> getMessagesFromUser(PeerId userId);
  List<ChatMessage> getRepliesTo(String cidString);

  // Statistics
  Future<SyncStats> getSyncStats();
  Future<Map<String, dynamic>> getDAGStats();
  Future<PeerStats> getPeerStats();
  Map<String, dynamic> getConnectionStats();

  // Manual operations
  Future<List<dynamic>>
  discoverPeers(); // Returns TransportPeer for new, different type for old
  Future<List<SyncResult>> syncWithAllPeers();

  // Error handling
  void clearError();

  // Lifecycle
  Future<void> dispose();
}
