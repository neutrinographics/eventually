import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' hide debugPrint;
import 'package:flutter/material.dart' hide debugPrint;
import 'package:eventually/eventually.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_peer.dart';
import '../transports/chat_nearby_transport.dart';
import 'hive_dag_store.dart';
import 'permissions_service.dart';

/// Modern chat service using the new Transport interface.
///
/// This service demonstrates the new transport architecture by implementing
/// a distributed chat system using the clean separation between transport,
/// protocol, and application layers.
///
/// Key improvements:
/// - Clean separation of transport and protocol layers
/// - Pluggable transport implementations
/// - Better error handling and connection management
/// - Simplified peer lifecycle management
class ModernChatService with ChangeNotifier {
  static const String _userNameKey = 'user_name_eventually';
  static const String _userIdKey = 'user_id_eventually';

  PeerId? _userId;
  String? _userName;

  late final HiveDAGStore _store;
  late final DAG _dag;
  late final ChatNearbyTransport _transport;
  late final ModernTransportPeerManager _peerManager;
  late final DefaultSynchronizer _synchronizer;

  final List<ChatMessage> _messages = [];
  final Map<PeerId, ChatPeer> _peers = {};
  final Map<PeerId, UserPresence> _userPresence = {};

  StreamSubscription<SyncEvent>? _syncEventSubscription;
  StreamSubscription<PeerEvent>? _peerEventSubscription;
  StreamSubscription<IncomingBytes>? _incomingBytesSubscription;
  Timer? _presenceTimer;

  bool _isInitialized = false;
  bool _isStarted = false;
  String? _error;

  // Getters
  PeerId? get userId => _userId;
  String? get userName => _userName;
  bool get isInitialized => _isInitialized;
  bool get isStarted => _isStarted;
  String? get error => _error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  Iterable<ChatPeer> get peers => _peers.values;
  Iterable<ChatPeer> get onlinePeers => _peers.values.where(
    (peer) => _userPresence[peer.id] == UserPresence.online,
  );

  int get messageCount => _messages.length;
  int get peerCount => _peers.length;
  int get onlinePeerCount => onlinePeers.length;
  bool get hasConnectedPeers => _peerManager.connectedPeers.isNotEmpty;

  /// Sets the user name and saves it to preferences.
  Future<void> setUserName(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('User name cannot be empty');
    }

    _userName = name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, _userName!);

    debugPrint('User name set to: $_userName');
    notifyListeners();
  }

  /// Initializes the chat service.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _error = null;
      notifyListeners();

      // Check permissions first
      final permissionsService = PermissionsService();
      final hasPermissions = await permissionsService.requestAllPermissions();
      if (!hasPermissions) {
        throw Exception('Required permissions not granted');
      }

      await _loadUserInfo();

      if (_userId == null || _userName == null) {
        throw Exception('User information not available');
      }

      // Initialize storage
      _store = HiveDAGStore();
      await _store.initialize();
      _dag = DAG();

      // Initialize transport
      _transport = ChatNearbyTransport(
        nodeId: _userId!.value,
        displayName: _userName!,
      );

      // Initialize peer manager with transport
      final config = PeerConfig(
        nodeId: _userId!,
        displayName: _userName!,
        autoConnect: true,
        maxConnections: 10,
        connectionTimeout: const Duration(seconds: 8),
        discoveryInterval: const Duration(seconds: 30),
        enableHealthCheck: true,
        healthCheckInterval: const Duration(seconds: 60),
      );

      _peerManager = ModernTransportPeerManager(
        transport: _transport,
        config: config,
      );

      // Initialize synchronizer
      _synchronizer = DefaultSynchronizer(
        store: _store,
        dag: _dag,
        peerManager: _peerManager,
      );

      await _peerManager.initialize();
      await _loadExistingData();
      _setupEventListeners();

      _isInitialized = true;
      debugPrint('✅ Modern chat service initialized');
      notifyListeners();
    } catch (e, stackTrace) {
      _error = 'Failed to initialize: ${e.toString()}';
      debugPrint('❌ Initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  /// Starts the chat service and begins peer discovery.
  Future<void> start() async {
    if (!_isInitialized) {
      throw StateError('Service must be initialized before starting');
    }

    if (_isStarted) return;

    try {
      _error = null;
      notifyListeners();

      await _peerManager.startDiscovery();
      _synchronizer.startContinuousSync(interval: const Duration(seconds: 45));

      // Start announcing presence
      _startPresenceAnnouncement();

      _isStarted = true;
      debugPrint('🚀 Modern chat service started');
      notifyListeners();
    } catch (e, stackTrace) {
      _error = 'Failed to start: ${e.toString()}';
      debugPrint('❌ Start failed: $e');
      debugPrint('Stack trace: $stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  /// Stops the chat service.
  Future<void> stop() async {
    if (!_isStarted) return;

    try {
      _presenceTimer?.cancel();
      _synchronizer.stopContinuousSync();
      await _peerManager.stopDiscovery();

      _isStarted = false;
      debugPrint('🛑 Modern chat service stopped');
      notifyListeners();
    } catch (e, stackTrace) {
      _error = 'Failed to stop: ${e.toString()}';
      debugPrint('❌ Stop failed: $e');
      debugPrint('Stack trace: $stackTrace');
      notifyListeners();
    }
  }

  /// Sends a chat message.
  Future<void> sendMessage(
    String content, {
    String? replyToCid,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isStarted) {
      throw StateError('Service must be started to send messages');
    }

    if (content.trim().isEmpty) {
      throw ArgumentError('Message content cannot be empty');
    }

    try {
      final message = ChatMessage.create(
        content: content.trim(),
        senderId: _userId!.value,
        senderName: _userName!,
        replyToId: replyToCid,
      );

      // Store the block
      await _store.put(message.block);
      _dag.addBlock(message.block);

      // Add to local messages and notify
      _messages.add(message);
      _sortMessages();
      notifyListeners();

      // Announce the new block to peers
      await _synchronizer.announceBlocks({message.cid});

      debugPrint('📤 Message sent: ${message.content}');
    } catch (e, stackTrace) {
      _error = 'Failed to send message: ${e.toString()}';
      debugPrint('❌ Send message failed: $e');
      debugPrint('Stack trace: $stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  /// Gets a message by its CID.
  ChatMessage? getMessageByCid(String cidString) {
    try {
      return _messages.firstWhere((msg) => msg.cid == cidString);
    } catch (e) {
      return null;
    }
  }

  /// Gets all messages from a specific user.
  List<ChatMessage> getMessagesFromUser(PeerId userId) {
    return _messages.where((msg) => msg.senderId == userId).toList();
  }

  /// Gets all replies to a specific message.
  List<ChatMessage> getRepliesTo(String cidString) {
    return _messages.where((msg) => msg.replyToId == cidString).toList();
  }

  /// Gets synchronization statistics.
  Future<SyncStats> getSyncStats() async {
    return await _synchronizer.getStats();
  }

  /// Gets DAG statistics.
  Future<Map<String, dynamic>> getDAGStats() async {
    final totalBlocks = await _store.getAllBlocks();
    final rootBlocks = _dag.rootBlocks;

    return {
      'total_blocks': totalBlocks.length,
      'root_blocks': rootBlocks.length,
      'messages': _messages.length,
    };
  }

  /// Gets peer statistics.
  Future<PeerStats> getPeerStats() async {
    return await _peerManager.getStats();
  }

  /// Gets transport connection statistics.
  Map<String, dynamic> getConnectionStats() {
    return {
      'connected_peers': _transport.connectedUserCount,
      'discovered_peers': _transport.discoveredPeers.length,
      'transport_ready': _transport.isReady,
    };
  }

  /// Manually discovers peers.
  Future<List<TransportPeer>> discoverPeers() async {
    try {
      final peers = await _transport.discoverPeers(
        timeout: const Duration(seconds: 5),
      );
      debugPrint('🔍 Discovered ${peers.length} peers');
      return peers;
    } catch (e) {
      debugPrint('❌ Discovery failed: $e');
      return [];
    }
  }

  /// Manually syncs with all connected peers.
  Future<List<SyncResult>> syncWithAllPeers() async {
    try {
      final results = await _synchronizer.syncWithAllPeers();
      debugPrint('🔄 Sync completed with ${results.length} peers');
      return results;
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
      return [];
    }
  }

  /// Clears any error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Private methods

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();

    _userName = prefs.getString(_userNameKey);
    String? userIdString = prefs.getString(_userIdKey);

    if (userIdString == null) {
      // Generate new user ID
      userIdString = const Uuid().v4();
      await prefs.setString(_userIdKey, userIdString);
      debugPrint('Generated new user ID: $userIdString');
    }

    _userId = PeerId(userIdString);
    debugPrint('Loaded user: $_userName (${_userId?.value})');
  }

  Future<void> _loadExistingData() async {
    try {
      final allBlocks = await _store.getAllBlocks();
      debugPrint('📦 Loading ${allBlocks.length} existing blocks');

      for (final block in allBlocks) {
        _dag.addBlock(block);
        await _processBlock(block);
      }

      _sortMessages();
      debugPrint('💬 Loaded ${_messages.length} messages');
    } catch (e) {
      debugPrint('⚠️ Error loading existing data: $e');
    }
  }

  void _setupEventListeners() {
    // Listen to sync events
    _syncEventSubscription = _synchronizer.syncEvents.listen(
      _handleSyncEvent,
      onError: (e) => debugPrint('Sync event error: $e'),
    );

    // Listen to peer events
    _peerEventSubscription = _peerManager.peerEvents.listen(
      _handlePeerEvent,
      onError: (e) => debugPrint('Peer event error: $e'),
    );

    // Listen to incoming bytes for direct transport handling if needed
    _incomingBytesSubscription = _transport.incomingBytes.listen((
      incomingBytes,
    ) {
      // This is handled by the peer manager, but we can log it
      debugPrint(
        '📨 Received ${incomingBytes.bytes.length} bytes from ${incomingBytes.peer.displayName}',
      );
    }, onError: (e) => debugPrint('Incoming bytes error: $e'));
  }

  void _handleSyncEvent(SyncEvent event) {
    switch (event) {
      case SyncStarted(peer: final peer):
        debugPrint('🔄 Sync started with ${peer.displayName}');
        break;
      case SyncCompleted(result: final result):
        debugPrint(
          '✅ Sync completed with ${result.peer.displayName}: '
          '${result.blocksReceived} blocks received',
        );
        _processSyncResult(result);
        break;
      case SyncFailed(peer: final peer, error: final error):
        debugPrint(
          '❌ Sync failed with ${peer?.displayName ?? "unknown"}: $error',
        );
        break;
      case BlocksDiscovered(blocks: final blocks, peer: final peer):
        debugPrint(
          '📦 Discovered ${blocks.length} blocks from ${peer.displayName}',
        );
        break;
      case BlocksFetched(blocks: final blocks, peer: final peer):
        debugPrint(
          '📥 Fetched ${blocks.length} blocks from ${peer.displayName}',
        );
        _processNewBlocks(blocks.toList());
        break;
    }
  }

  void _handlePeerEvent(PeerEvent event) {
    switch (event) {
      case PeerConnected(peer: final peer):
        debugPrint('🤝 Peer connected: ${peer.displayName}');
        _addOrUpdatePeer(peer);
        _updatePeerPresence(peer.id, UserPresence.online);
        break;
      case PeerDiscovered(peer: final peer):
        debugPrint('👋 Peer discovered: ${peer.displayName}');
        _addOrUpdatePeer(peer);
        break;
      case PeerDisconnected(peer: final peer):
        debugPrint('👋 Peer disconnected: ${peer.displayName}');
        _updatePeerPresence(peer.id, UserPresence.offline);
        break;
      case MessageReceived(message: final message, peer: final peer):
        debugPrint('📨 Message received from ${peer.displayName}');
        break;
    }
    notifyListeners();
  }

  void _processSyncResult(SyncResult result) {
    if (result.success && result.blocksReceived > 0) {
      // Blocks were added during sync, refresh our message list
      _reloadMessagesFromDAG();
    }
  }

  Future<void> _processNewBlocks(List<Block> blocks) async {
    for (final block in blocks) {
      await _processBlock(block);
    }
    _sortMessages();
    notifyListeners();
  }

  Future<void> _processBlock(Block block) async {
    try {
      final data = String.fromCharCodes(block.data);
      final json = jsonDecode(data) as Map<String, dynamic>;

      if (json['type'] == 'chat_message') {
        final message = ChatMessage.fromBlock(block);

        // Check if we already have this message
        final existingIndex = _messages.indexWhere((m) => m.cid == message.cid);
        if (existingIndex == -1) {
          _messages.add(message);
          debugPrint(
            '💬 New message from ${message.senderName}: ${message.content}',
          );
        }
      } else if (json['type'] == 'user_presence') {
        final userId = PeerId(json['user_id'] as String);
        final presence = UserPresence.values.firstWhere(
          (p) => p.name == json['presence'],
          orElse: () => UserPresence.offline,
        );
        _updatePeerPresence(userId, presence);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to process block ${block.cid}: $e');
    }
  }

  void _updatePeerPresence(PeerId peerId, UserPresence presence) {
    _userPresence[peerId] = presence;

    final peer = _peers[peerId];
    if (peer != null) {
      final isOnline = presence == UserPresence.online;
      _peers[peerId] = peer.copyWith(
        isOnline: isOnline,
        lastSeen: DateTime.now(),
      );
    }
  }

  void _addOrUpdatePeer(Peer peer) {
    final chatPeer =
        _peers[peer.id] ??
        ChatPeer(
          id: peer.id,
          name: peer.displayName,
          isOnline: false,
          lastSeen: DateTime.now(),
        );

    _peers[peer.id] = chatPeer.copyWith(
      name: peer.displayName,
      isOnline: peer.isActive,
      lastSeen: DateTime.now(),
    );
  }

  void _startPresenceAnnouncement() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _announcePresence();
    });

    // Send initial presence
    _announcePresence();
  }

  Future<void> _announcePresence() async {
    try {
      final presenceData = {
        'type': 'user_presence',
        'user_id': _userId!.value,
        'user_name': _userName!,
        'presence': UserPresence.online.name,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final dataBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(presenceData)),
      );
      final block = Block.fromData(dataBytes);
      await _store.put(block);
      _dag.addBlock(block);
      await _synchronizer.announceBlocks({block.cid});
    } catch (e) {
      debugPrint('⚠️ Failed to announce presence: $e');
    }
  }

  Future<void> _reloadMessagesFromDAG() async {
    _messages.clear();
    final allBlocks = await _store.getAllBlocks();

    for (final block in allBlocks) {
      await _processBlock(block);
    }

    _sortMessages();
  }

  void _sortMessages() {
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<void> dispose() async {
    await _syncEventSubscription?.cancel();
    await _peerEventSubscription?.cancel();
    await _incomingBytesSubscription?.cancel();
    _presenceTimer?.cancel();

    if (_isInitialized) {
      await stop();
      await _peerManager.dispose();
      await _synchronizer.close();
      await _store.close();
    }

    super.dispose();
  }
}

/// User presence states.
enum UserPresence { online, offline, away }

void debugPrint(String message) {
  if (kDebugMode) {
    print('[ModernChatService] $message');
  }
}
