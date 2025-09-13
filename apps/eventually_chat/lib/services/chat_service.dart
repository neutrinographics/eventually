import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide debugPrint;
import 'package:eventually/eventually.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transport/transport.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_peer.dart';
import '../transports/nearby_transport_protocol.dart';
import 'hive_dag_store.dart';
import 'permissions_service.dart';

/// Chat service using the Eventually library for Merkle DAG synchronization.
///
/// This service demonstrates the transport architecture by implementing
/// a distributed chat system using the clean separation between transport,
/// protocol, and application layers.
///
/// Key features:
/// - Clean separation of transport and protocol layers
/// - Pluggable transport implementations
/// - Better error handling and connection management
/// - Simplified peer lifecycle management
class ChatService with ChangeNotifier {
  static const String _userNameKey = 'user_name_eventually';
  static const String _userIdKey = 'user_id_eventually';

  PeerId? _userId;
  String? _userName;

  late final HiveDAGStore _store;
  late final DAG _dag;
  late final NearbyTransportProtocol _transportProtocol;
  late final TransportManager _transportManager;
  late final EventuallySynchronizer _synchronizer;

  final List<ChatMessage> _messages = [];
  final Map<PeerId, ChatPeer> _peers = {};
  final Map<PeerId, UserPresence> _userPresence = {};

  StreamSubscription<SyncEvent>? _syncEventSubscription;
  StreamSubscription<Peer>? _peerUpdatesSubscription;
  StreamSubscription<TransportMessage>? _messageSubscription;
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
  bool get hasConnectedPeers => _transportManager.peers
      .where((p) => p.status == PeerStatus.connected)
      .isNotEmpty;

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

      // Initialize transport protocol
      _transportProtocol = NearbyTransportProtocol(
        serviceId: 'eventually_chat',
        userName: _userName!,
      );

      // Initialize transport manager
      final config = TransportConfig(
        localPeerId: _userId!,
        protocol: _transportProtocol,
        discoveryInterval: const Duration(seconds: 5),
      );
      _transportManager = TransportManager(config);

      // Initialize synchronizer
      _synchronizer = EventuallySynchronizer(store: _store, dag: _dag);

      await _synchronizer.initialize(_transportManager);
      await _loadExistingData();
      _setupEventListeners();

      _isInitialized = true;
      debugPrint('✅ Chat service initialized');
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

      await _transportManager.start();

      // Start announcing presence
      _startPresenceAnnouncement();

      _isStarted = true;
      debugPrint('🚀 Chat service started');
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
      await _transportManager.stop();

      _isStarted = false;
      debugPrint('🛑 Chat service stopped');
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

      // Add block to synchronizer (this will store it and add to DAG)
      await _synchronizer.addBlock(message.block);

      // Add to local messages and notify
      _messages.add(message);
      _sortMessages();
      notifyListeners();

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
      return _messages.firstWhere((msg) => msg.cid.toString() == cidString);
    } catch (e) {
      return null;
    }
  }

  /// Gets all messages from a specific user.
  List<ChatMessage> getMessagesFromUser(PeerId userId) {
    return _messages.where((msg) => msg.senderId == userId.value).toList();
  }

  /// Gets all replies to a specific message.
  List<ChatMessage> getRepliesTo(String cidString) {
    return _messages.where((msg) => msg.replyToId == cidString).toList();
  }

  /// Gets synchronization statistics.
  SyncStats getSyncStats() {
    return _synchronizer.stats;
  }

  /// Gets DAG statistics.
  Future<Map<String, dynamic>> getDAGStats() async {
    final allBlocks = <Block>[];
    await for (final cid in _store.listCids()) {
      final block = await _store.get(cid);
      if (block != null) {
        allBlocks.add(block);
      }
    }

    final stats = _dag.calculateStats();

    return {
      'total_blocks': allBlocks.length,
      'root_blocks': stats.rootBlocks,
      'messages': _messages.length,
      'total_size': stats.totalSize,
      'max_depth': stats.maxDepth,
      'avg_depth': stats.averageDepth,
    };
  }

  /// Gets transport connection statistics.
  Map<String, dynamic> getConnectionStats() {
    final connectedCount = _transportManager.peers
        .where((p) => p.status == PeerStatus.connected)
        .length;
    final discoveredCount = _transportManager.peers.length;

    return {
      'connected_peers': connectedCount,
      'discovered_peers': discoveredCount,
      'transport_ready': _transportManager.isStarted,
    };
  }

  /// Manually discovers peers.
  Future<void> discoverPeers() async {
    try {
      // Discovery is now automatic and periodic
      debugPrint('🔍 Peer discovery is automatic in new transport design');
    } catch (e) {
      debugPrint('❌ Discovery failed: $e');
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
      final allCids = <CID>[];
      await for (final cid in _store.listCids()) {
        allCids.add(cid);
      }

      debugPrint('📦 Loading ${allCids.length} existing blocks');

      for (final cid in allCids) {
        final block = await _store.get(cid);
        if (block != null) {
          _dag.addBlock(block);
          await _processBlock(block);
        }
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

    // Listen to peer updates
    _peerUpdatesSubscription = _transportManager.peerUpdates.listen(
      _handlePeerUpdate,
      onError: (e) => debugPrint('Peer update error: $e'),
    );

    // Listen to received messages (handled by synchronizer, but we can log them)
    // Listen to messages received
    _messageSubscription = _transportManager.messagesReceived.listen(
      _handleReceivedMessage,
      onError: (e) => debugPrint('Message received error: $e'),
    );

    // Note: Connection and discovery events are now handled internally by TransportManager
  }

  void _handleSyncEvent(SyncEvent event) {
    switch (event) {
      case BlocksAnnounced(cids: final cids):
        debugPrint('📢 Announced ${cids.length} blocks');
        break;
      case BlocksRequested(cids: final cids):
        debugPrint('📞 Requested ${cids.length} blocks');
        break;
      case BlockReceived(cid: final cid, fromPeer: final peer):
        debugPrint(
          '📥 Received block ${cid.toString().substring(0, 8)}... from ${peer.value}',
        );
        _processReceivedBlock(cid);
        break;
      case SyncError(error: final error):
        debugPrint('❌ Sync error: $error');
        break;
    }
  }

  void _handlePeerUpdate(Peer peer) {
    debugPrint('👤 Peer update: ${peer.id.value} - ${peer.status}');

    _addOrUpdatePeer(peer);

    switch (peer.status) {
      case PeerStatus.connected:
        _updatePeerPresence(peer.id, UserPresence.online);
        // Announce all our existing blocks to the newly connected peer
        _announceHistoricBlocks();
        break;
      case PeerStatus.disconnected:
      case PeerStatus.failed:
        _updatePeerPresence(peer.id, UserPresence.offline);
        break;
      default:
        // For discovered, connecting, disconnecting - keep current status
        break;
    }

    notifyListeners();
  }

  void _handleReceivedMessage(TransportMessage message) {
    // Messages are handled by the synchronizer, but we can log them
    debugPrint('📨 Received message from ${message.senderId.value}');
  }

  Future<void> _processReceivedBlock(CID cid) async {
    final block = await _store.get(cid);
    if (block != null) {
      await _processBlock(block);
      _sortMessages();
      notifyListeners();
    }
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

  void _addOrUpdatePeer(Peer transportPeer) {
    final displayName =
        transportPeer.metadata['displayName'] as String? ?? 'Unknown';

    final chatPeer =
        _peers[transportPeer.id] ??
        ChatPeer(
          id: transportPeer.id,
          name: displayName,
          isOnline: false,
          lastSeen: DateTime.now(),
        );

    _peers[transportPeer.id] = chatPeer.copyWith(
      name: displayName,
      isOnline: transportPeer.status == PeerStatus.connected,
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
      await _synchronizer.addBlock(block);
    } catch (e) {
      debugPrint('⚠️ Failed to announce presence: $e');
    }
  }

  /// Announces all existing blocks to newly connected peers
  Future<void> _announceHistoricBlocks() async {
    try {
      // Get all CIDs from the DAG
      final allCids = _dag.cids.toSet();

      if (allCids.isNotEmpty) {
        debugPrint('📢 Announcing ${allCids.length} historic blocks to peers');
        await _synchronizer.announceBlocks(allCids);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to announce historic blocks: $e');
    }
  }

  void _sortMessages() {
    _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<void> dispose() async {
    await _syncEventSubscription?.cancel();
    await _peerUpdatesSubscription?.cancel();
    await _messageSubscription?.cancel();
    _presenceTimer?.cancel();

    if (_isInitialized) {
      await stop();
      await _synchronizer.dispose();
      await _transportManager.dispose();
      await _store.close();
    }

    super.dispose();
  }
}

/// User presence states.
enum UserPresence { online, offline, away }

void debugPrint(String message) {
  if (kDebugMode) {
    print('[ChatService] $message');
  }
}
