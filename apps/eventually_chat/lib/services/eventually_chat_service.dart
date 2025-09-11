import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide debugPrint;
import 'package:flutter/material.dart' hide debugPrint;
import 'package:eventually/eventually.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_peer.dart';
import 'hive_dag_store.dart';
import 'nearby_peer_manager.dart';
import 'permissions_service.dart';

/// Chat service using the Eventually library for Merkle DAG synchronization.
///
/// This service demonstrates the capabilities of the Eventually library by
/// implementing a distributed chat system where messages are stored as
/// content-addressed blocks in a Merkle DAG and synchronized between peers.
///
/// Key features:
/// - Messages stored as blocks in content-addressed storage
/// - Automatic synchronization of chat history between peers
/// - Merkle DAG structure for efficient data verification
/// - Peer-to-peer networking for distributed communication
class EventuallyChatService with ChangeNotifier {
  static const String _userNameKey = 'user_name_eventually';
  static const String _userIdKey = 'user_id_eventually';

  PeerId? _userId;
  String? _userName;

  late final HiveDAGStore _store;
  late final DAG _dag;
  late NearbyPeerManager _peerManager;
  late final Synchronizer _synchronizer;

  final List<ChatMessage> _messages = [];
  final Map<PeerId, ChatPeer> _peers = {};
  final Map<PeerId, UserPresence> _userPresence = {};

  StreamSubscription<SyncEvent>? _syncEventSubscription;
  StreamSubscription<PeerEvent>? _peerEventSubscription;
  Timer? _presenceTimer;

  bool _isInitialized = false;
  bool _isStarted = false;
  String? _error;

  EventuallyChatService();

  // Getters
  String? get userId => _userId?.value;
  String? get userName => _userName;
  bool get isInitialized => _isInitialized;
  bool get isStarted => _isStarted;
  String? get error => _error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<ChatPeer> get peers =>
      _peers.values.where((p) => p.id != _userId).toList();
  List<ChatPeer> get onlinePeers => peers.where((p) => p.isOnline).toList();

  int get messageCount => _messages.length;
  int get peerCount => peers.length;
  int get onlinePeerCount => onlinePeers.length;
  bool get hasConnectedPeers => onlinePeerCount > 0;

  /// Sets the user name for this chat service.
  Future<void> setUserName(String userName) async {
    if (_isInitialized) {
      throw StateError('Cannot change user name after service is initialized');
    }

    _userName = userName.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, _userName!);

    debugPrint('✅ Username set to: $_userName');
    notifyListeners();
  }

  /// Initialize the chat service.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🚀 Initializing EventuallyChatService...');

      // Request permissions
      final permissionsService = PermissionsService();
      final hasPermissions = await permissionsService.requestAllPermissions();
      if (!hasPermissions) {
        throw Exception('Required permissions not granted');
      }
      debugPrint('✅ Permissions granted');

      // Load user info
      await _loadUserInfo();
      debugPrint('📱 User info loaded: $_userName ($_userId)');

      // Initialize storage
      _store = HiveDAGStore();
      await _store.initialize();

      // Initialize DAG
      _dag = DAG();

      // Initialize peer manager using nearby connections
      _peerManager = NearbyPeerManager.nearby(
        nodeId: _userId!,
        displayName: _userName!,
      );

      // Initialize synchronizer
      _synchronizer = DefaultSynchronizer(
        store: _store,
        dag: _dag,
        peerManager: _peerManager,
      );

      // Set up event listeners
      _setupEventListeners();

      // Load existing data from storage
      await _loadExistingData();

      _isInitialized = true;
      _error = null;
      notifyListeners();

      debugPrint('✅ EventuallyChatService initialized successfully');
    } catch (e, stackTrace) {
      _error = 'Failed to initialize chat service: $e';
      debugPrint('❌ $_error');
      debugPrint(stackTrace.toString());
      notifyListeners();
      rethrow;
    }
  }

  /// Start the chat service.
  Future<void> start() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isStarted) return;

    try {
      debugPrint('▶️ Starting EventuallyChatService');

      // Start peer manager
      await _peerManager.startDiscovery();

      // Announce presence
      await _announcePresence(true);

      // Start continuous sync
      _synchronizer.startContinuousSync(interval: const Duration(seconds: 10));

      // Start periodic presence announcements
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _announcePresence(true),
      );

      _isStarted = true;
      notifyListeners();

      debugPrint('✅ EventuallyChatService started successfully');
    } catch (e) {
      _error = 'Failed to start chat service: $e';
      debugPrint('❌ $_error');
      notifyListeners();
      rethrow;
    }
  }

  /// Stop the chat service.
  Future<void> stop() async {
    if (!_isStarted) return;

    try {
      debugPrint('⏹️ Stopping EventuallyChatService');

      // Announce departure
      await _announcePresence(false);

      // Stop timers
      _presenceTimer?.cancel();
      _presenceTimer = null;

      // Stop synchronizer
      _synchronizer.stopContinuousSync();

      // Stop peer manager
      await _peerManager.stopDiscovery();

      // Cancel subscriptions
      await _syncEventSubscription?.cancel();
      await _peerEventSubscription?.cancel();

      // Close storage
      await _store.close();

      _isStarted = false;
      notifyListeners();

      debugPrint('✅ EventuallyChatService stopped successfully');
    } catch (e) {
      _error = 'Failed to stop chat service: $e';
      debugPrint('❌ $_error');
      notifyListeners();
    }
  }

  /// Send a chat message.
  Future<ChatMessage> sendMessage(String content, {String? replyToId}) async {
    if (!_isStarted) {
      throw StateError('Chat service not started');
    }

    if (content.trim().isEmpty) {
      throw ArgumentError('Message content cannot be empty');
    }

    try {
      // Create message
      final message = ChatMessage.create(
        senderId: _userId!.value,
        senderName: _userName!,
        content: content.trim(),
        replyToId: replyToId,
      );

      // Store block in DAG
      final success = await _store.put(message.block);
      if (!success) {
        throw Exception('Failed to store message block');
      }
      _dag.addBlock(message.block);

      // Add to messages list
      _messages.add(message);
      _sortMessages();

      // Announce to peers that we have this block
      await _synchronizer.announceBlocks({message.cid});

      debugPrint('📤 Sent message: ${message.content}');
      notifyListeners();

      return message;
    } catch (e) {
      debugPrint('❌ Failed to send message: $e');
      rethrow;
    }
  }

  /// Get a message by its CID.
  ChatMessage? getMessageByCid(CID cid) {
    try {
      return _messages.firstWhere((m) => m.cid == cid);
    } catch (e) {
      return null;
    }
  }

  /// Get messages from a specific user.
  List<ChatMessage> getMessagesFromUser(String userId) {
    return _messages.where((m) => m.senderId == userId).toList();
  }

  /// Get replies to a specific message.
  List<ChatMessage> getRepliesTo(String messageId) {
    return _messages.where((m) => m.replyToId == messageId).toList();
  }

  /// Get sync statistics.
  Future<SyncStats> getSyncStats() async {
    return await _synchronizer.getStats();
  }

  /// Get DAG statistics.
  DAGStats getDAGStats() {
    return _dag.calculateStats();
  }

  /// Get peer statistics.
  Future<PeerStats> getPeerStats() async {
    return await _peerManager.getStats();
  }

  /// Get overall connection statistics.
  Future<Map<String, dynamic>> getConnectionStats() async {
    final syncStats = await getSyncStats();
    final storeStats = await _store.getStats();

    return {
      'userId': _userId,
      'userName': _userName,
      'isInitialized': _isInitialized,
      'isStarted': _isStarted,
      'messageCount': messageCount,
      'peerCount': peerCount,
      'onlinePeerCount': onlinePeerCount,
      'dagBlocks': storeStats.totalBlocks,
      'dagSize': storeStats.totalSize,
      'syncCount': syncStats.totalSyncs,
      'syncSuccess': syncStats.successfulSyncs,
      'syncSuccessRate': syncStats.successRate,
    };
  }

  /// Manually trigger peer discovery.
  Future<void> discoverPeers() async {
    if (!_isStarted) return;

    try {
      await _peerManager.startDiscovery();
      debugPrint('🔍 Triggered peer discovery');
    } catch (e) {
      debugPrint('❌ Peer discovery failed: $e');
    }
  }

  /// Manually trigger synchronization.
  Future<void> syncWithAllPeers() async {
    if (!_isStarted) return;

    try {
      await _synchronizer.syncWithAllPeers();
      debugPrint('🔄 Triggered sync with all peers');
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
    }
  }

  /// Clear error state.
  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  // Private methods

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();

    _userName = prefs.getString(_userNameKey);
    final userIdString = prefs.getString(_userIdKey);
    if (userIdString != null) {
      _userId = PeerId(userIdString);
    }

    // Generate new user ID if none exists
    if (_userId == null) {
      final userIdString = const Uuid().v4();
      _userId = PeerId(userIdString);
      await prefs.setString(_userIdKey, userIdString);
      debugPrint('🆔 Generated new user ID: $_userId');
    }

    debugPrint('📱 Loaded user: $_userName ($_userId)');
  }

  Future<void> _loadExistingData() async {
    try {
      debugPrint('📚 Loading existing data from storage...');

      // Get all blocks from storage
      final allCids = <CID>[];
      await for (final cid in _store.listCids()) {
        allCids.add(cid);
      }
      debugPrint('🔍 Found ${allCids.length} blocks in storage');

      for (final cid in allCids) {
        final block = await _store.get(cid);
        if (block != null) {
          _dag.addBlock(block);
          await _processBlock(block);
        }
      }

      _sortMessages();
      debugPrint(
        '✅ Loaded ${_messages.length} messages and ${_userPresence.length} presence records',
      );
    } catch (e) {
      debugPrint('❌ Error loading existing data: $e');
    }
  }

  void _setupEventListeners() {
    // Listen for sync events
    _syncEventSubscription = _synchronizer.syncEvents.listen(
      (event) => _handleSyncEvent(event),
      onError: (error) => debugPrint('❌ Sync event error: $error'),
    );

    // Listen for peer events
    _peerEventSubscription = _peerManager.peerEvents.listen(
      (event) => _handlePeerEvent(event),
      onError: (error) => debugPrint('❌ Peer event error: $error'),
    );
  }

  void _handleSyncEvent(SyncEvent event) {
    switch (event) {
      case SyncStarted():
        debugPrint('🔄 Sync started with peer: ${event.peer.id}');
        break;
      case SyncCompleted():
        debugPrint('✅ Sync completed with peer: ${event.result.peer.id}');
        _processSyncResult(event.result);
        break;
      case SyncFailed():
        debugPrint(
          '❌ Sync failed with peer: ${event.peer?.id} - ${event.error}',
        );
        break;
      case BlocksDiscovered():
        debugPrint(
          '🔍 Discovered ${event.blocks.length} blocks from peer: ${event.peer.id}',
        );
        break;
      case BlocksFetched():
        debugPrint(
          '📥 Fetched ${event.blocks.length} blocks from peer: ${event.peer.id}',
        );
        _processNewBlocks(event.blocks);
        break;
    }
  }

  void _handlePeerEvent(PeerEvent event) {
    switch (event) {
      case PeerDiscovered():
        debugPrint('🔍 Peer discovered: ${event.peer.id}');
        _addOrUpdatePeer(
          ChatPeer.fromPeer(
            event.peer,
            name: event.peer.metadata['name'] as String? ?? 'Unknown',
            status: ChatPeerStatus.discovered,
            isOnline: false,
          ),
        );
        break;
      case PeerConnected():
        debugPrint('👋 Peer connected: ${event.peer.id}');
        _addOrUpdatePeer(
          ChatPeer.fromPeer(
            event.peer,
            name: event.peer.metadata['name'] as String? ?? 'Unknown',
            status: ChatPeerStatus.connected,
            isOnline: true,
          ),
        );
        break;
      case PeerDisconnected():
        debugPrint('👋 Peer disconnected: ${event.peer.id}');
        _updatePeerStatus(event.peer.id, isOnline: false);
        break;
      case MessageReceived():
        // Handle direct peer messages if needed
        break;
    }
  }

  void _processSyncResult(SyncResult result) {
    if (result.success) {
      debugPrint(
        '📊 Sync stats: ${result.blocksReceived} received, ${result.blocksSent} sent',
      );
      notifyListeners();
    }
  }

  void _processNewBlocks(Set<Block> blocks) {
    for (final block in blocks) {
      _processBlock(block);
    }
    _sortMessages();
    notifyListeners();
  }

  Future<void> _processBlock(Block block) async {
    try {
      final jsonString = utf8.decode(block.data);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'chat_message':
          final message = ChatMessage.fromBlock(block);
          if (!_messages.any((m) => m.id == message.id)) {
            _messages.add(message);
            debugPrint('💬 Added message from ${message.senderName}');
          }
          break;
        case 'user_presence':
          final presence = UserPresence.fromBlock(block);
          _userPresence[PeerId(presence.userId)] = presence;
          _updatePeerPresence(presence);
          debugPrint(
            '👤 Updated presence for ${presence.userName}: ${presence.isOnline}',
          );
          break;
      }
    } catch (e) {
      debugPrint('❌ Error processing block ${block.cid}: $e');
    }
  }

  void _updatePeerPresence(UserPresence presence) {
    final presenceUserId = PeerId(presence.userId);
    final existingPeer = _peers[presenceUserId];
    if (existingPeer != null) {
      _peers[presenceUserId] = existingPeer.copyWith(
        name: presence.userName,
        isOnline: presence.isOnline,
        lastSeen: presence.timestamp,
      );
    } else if (presenceUserId != _userId) {
      // Create new peer from presence
      _peers[presenceUserId] = ChatPeer(
        id: presenceUserId,
        name: presence.userName,
        isOnline: presence.isOnline,
        lastSeen: presence.timestamp,
      );
    }
    notifyListeners();
  }

  void _addOrUpdatePeer(ChatPeer peer) {
    _peers[peer.id] = peer;
    notifyListeners();
  }

  void _updatePeerStatus(
    PeerId peerId, {
    bool? isOnline,
    ChatPeerStatus? status,
  }) {
    final peer = _peers[peerId];
    if (peer != null) {
      _peers[peerId] = peer.copyWith(
        isOnline: isOnline ?? peer.isOnline,
        status: status ?? peer.status,
        lastSeen: isOnline == false ? DateTime.now() : peer.lastSeen,
      );
      notifyListeners();
    }
  }

  Future<void> _announcePresence(bool isOnline) async {
    try {
      final presence = UserPresence.create(
        userId: _userId!.value,
        userName: _userName!,
        isOnline: isOnline,
      );

      // Store block in DAG
      final success = await _store.put(presence.block);
      if (!success) {
        debugPrint('❌ Failed to store presence block');
        return;
      }
      _dag.addBlock(presence.block);

      // Announce to peers
      await _synchronizer.announceBlocks({presence.cid});

      debugPrint('📢 Announced presence: $isOnline');
    } catch (e) {
      debugPrint('❌ Failed to announce presence: $e');
    }
  }

  void _sortMessages() {
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
