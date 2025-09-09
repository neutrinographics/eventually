import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:eventually/eventually.dart';
import 'package:uuid/uuid.dart';

/// Mock implementation of PeerManager for demonstration purposes.
///
/// This simulates peer-to-peer connections by creating virtual peers
/// and handling message exchange. In a real implementation, this would
/// be replaced with actual network transport (TCP, WebRTC, etc.).
class MockPeerManager implements PeerManager {
  final String userId;
  final List<Peer> _knownPeers = [];
  final Map<String, MockPeerConnection> _connections = {};
  final StreamController<PeerEvent> _peerEventsController =
      StreamController<PeerEvent>.broadcast();

  Timer? _discoveryTimer;
  Timer? _heartbeatTimer;
  bool _isDiscoveryActive = false;

  MockPeerManager({required this.userId});

  @override
  Iterable<Peer> get connectedPeers =>
      _connections.values.where((c) => c.isConnected).map((c) => c.peer);

  @override
  Stream<PeerEvent> get peerEvents => _peerEventsController.stream;

  /// Starts peer discovery simulation.
  Future<void> startDiscovery() async {
    if (_isDiscoveryActive) return;

    debugPrint('🔍 Starting mock peer discovery');
    _isDiscoveryActive = true;

    // Simulate finding peers periodically
    _discoveryTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _simulateDiscoveredPeer(),
    );

    // Simulate some initial peers
    await Future.delayed(const Duration(seconds: 2));
    for (int i = 0; i < 2; i++) {
      await _simulateDiscoveredPeer();
    }

    // Start heartbeat to simulate peer connections/disconnections
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _simulateNetworkChanges(),
    );
  }

  /// Stops peer discovery.
  Future<void> stopDiscovery() async {
    if (!_isDiscoveryActive) return;

    debugPrint('🛑 Stopping mock peer discovery');
    _isDiscoveryActive = false;

    _discoveryTimer?.cancel();
    _heartbeatTimer?.cancel();

    // Disconnect all peers
    for (final connection in _connections.values.toList()) {
      await connection.disconnect();
    }
  }

  /// Simulates discovering a new peer.
  Future<void> discoverPeers() async {
    if (!_isDiscoveryActive) return;
    await _simulateDiscoveredPeer();
  }

  @override
  Future<PeerConnection> connect(Peer peer) async {
    final existingConnection = _connections[peer.id];
    if (existingConnection != null) {
      if (existingConnection.isConnected) {
        return existingConnection;
      }
    }

    final connection = MockPeerConnection(peer);
    await connection.connect();

    _connections[peer.id] = connection;
    _peerEventsController.add(
      PeerConnected(peer: peer, timestamp: DateTime.now()),
    );

    debugPrint('🤝 Connected to peer: ${peer.id}');
    return connection;
  }

  @override
  Future<void> disconnect(String peerId) async {
    final connection = _connections[peerId];
    if (connection != null) {
      await connection.disconnect();
      _connections.remove(peerId);

      _peerEventsController.add(
        PeerDisconnected(
          peer: connection.peer,
          timestamp: DateTime.now(),
          reason: 'Manual disconnect',
        ),
      );

      debugPrint('👋 Disconnected from peer: $peerId');
    }
  }

  @override
  Future<void> disconnectAll() async {
    final peers = _connections.values.toList();
    for (final connection in peers) {
      await disconnect(connection.peer.id);
    }
  }

  @override
  Future<List<Peer>> findPeersWithBlock(CID cid) async {
    // Simulate that some random peers might have the block
    final candidatePeers = <Peer>[];
    for (final peer in connectedPeers) {
      // 50% chance that a peer has the block
      if (Random().nextBool()) {
        candidatePeers.add(peer);
      }
    }
    return candidatePeers;
  }

  @override
  Future<void> broadcast(Message message) async {
    for (final connection in _connections.values) {
      if (connection.isConnected) {
        try {
          await connection.sendMessage(message);
        } catch (e) {
          debugPrint('❌ Failed to broadcast to ${connection.peer.id}: $e');
        }
      }
    }
  }

  @override
  void addPeer(Peer peer) {
    if (!_knownPeers.any((p) => p.id == peer.id)) {
      _knownPeers.add(peer);
      debugPrint('📝 Added peer to known list: ${peer.id}');
    }
  }

  @override
  void removePeer(String peerId) {
    _knownPeers.removeWhere((p) => p.id == peerId);
    disconnect(peerId);
    debugPrint('🗑️ Removed peer from known list: $peerId');
  }

  @override
  Peer? getPeer(String peerId) {
    try {
      return _knownPeers.firstWhere((p) => p.id == peerId);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<PeerStats> getStats() async {
    return PeerStats(
      totalPeers: _knownPeers.length,
      connectedPeers: connectedPeers.length,
      totalMessages: _connections.values.fold(
        0,
        (sum, conn) => sum + conn.messagesSent + conn.messagesReceived,
      ),
      totalBytesReceived: _connections.values.fold(
        0,
        (sum, conn) => sum + conn.bytesReceived,
      ),
      totalBytesSent: _connections.values.fold(
        0,
        (sum, conn) => sum + conn.bytesSent,
      ),
      details: {
        'discoveryActive': _isDiscoveryActive,
        'knownPeers': _knownPeers.map((p) => p.id).toList(),
        'connectionStates': _connections.map(
          (id, conn) => MapEntry(id, conn.isConnected),
        ),
      },
    );
  }

  /// Simulates discovering a new peer.
  Future<void> _simulateDiscoveredPeer() async {
    // Don't create too many peers
    if (connectedPeers.length >= 5) return;

    final peerId = const Uuid().v4();
    final peerNames = [
      'Alice',
      'Bob',
      'Charlie',
      'Diana',
      'Eve',
      'Frank',
      'Grace',
      'Henry',
    ];
    final name = peerNames[Random().nextInt(peerNames.length)];

    final peer = Peer(
      id: peerId,
      address: 'mock://$peerId',
      metadata: {'name': name, 'type': 'mock'},
    );

    addPeer(peer);

    // Automatically connect to discovered peers
    try {
      await connect(peer);
    } catch (e) {
      debugPrint('❌ Failed to auto-connect to discovered peer: $e');
    }
  }

  /// Simulates network changes (peers joining/leaving).
  void _simulateNetworkChanges() {
    final random = Random();

    // 30% chance of a peer disconnecting
    if (random.nextDouble() < 0.3 && connectedPeers.isNotEmpty) {
      final peers = connectedPeers.toList();
      final randomPeer = peers[random.nextInt(peers.length)];
      disconnect(randomPeer.id);
    }

    // 40% chance of discovering a new peer
    if (random.nextDouble() < 0.4) {
      _simulateDiscoveredPeer();
    }
  }
}

/// Mock implementation of PeerConnection.
class MockPeerConnection implements PeerConnection {
  @override
  final Peer peer;

  final StreamController<Message> _messagesController =
      StreamController<Message>.broadcast();

  bool _isConnected = false;
  int messagesSent = 0;
  int messagesReceived = 0;
  int bytesSent = 0;
  int bytesReceived = 0;

  MockPeerConnection(this.peer);

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<Message> get messages => _messagesController.stream;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    // Simulate connection delay
    await Future.delayed(Duration(milliseconds: 100 + Random().nextInt(400)));

    // 90% success rate for connections
    if (Random().nextDouble() < 0.9) {
      _isConnected = true;
      debugPrint('✅ Mock connection established with ${peer.id}');
    } else {
      throw ConnectionException('Simulated connection failure', peer: peer);
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected) return;

    _isConnected = false;
    await _messagesController.close();
    debugPrint('🔌 Mock connection closed with ${peer.id}');
  }

  @override
  Future<void> sendMessage(dynamic message) async {
    if (!_isConnected) {
      throw ConnectionException('Not connected', peer: peer);
    }

    // Simulate message sending
    await Future.delayed(Duration(milliseconds: 10 + Random().nextInt(50)));

    if (message is Message) {
      final bytes = message.toBytes();
      bytesSent += bytes.length;
      messagesSent++;
    }

    debugPrint('📤 Sent message to ${peer.id}');
  }

  @override
  Future<Block?> requestBlock(CID cid) async {
    if (!_isConnected) {
      throw ConnectionException('Not connected', peer: peer);
    }

    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 50 + Random().nextInt(200)));

    // 70% chance that peer has the block
    if (Random().nextDouble() < 0.7) {
      // Create a mock block (in real implementation, this would be real data)
      final mockData = Uint8List.fromList(
        'mock-block-data-${cid.toString().substring(0, 8)}'.codeUnits,
      );
      return Block.withCid(cid, mockData);
    }

    return null; // Peer doesn't have the block
  }

  @override
  Future<List<Block>> requestBlocks(List<CID> cids) async {
    final blocks = <Block>[];
    for (final cid in cids) {
      final block = await requestBlock(cid);
      if (block != null) {
        blocks.add(block);
      }
    }
    return blocks;
  }

  @override
  Future<void> sendBlock(Block block) async {
    if (!_isConnected) {
      throw ConnectionException('Not connected', peer: peer);
    }

    await Future.delayed(Duration(milliseconds: 20 + Random().nextInt(100)));
    bytesSent += block.size;
    messagesSent++;
    debugPrint('📤 Sent block ${block.cid} to ${peer.id}');
  }

  @override
  Future<bool> hasBlock(CID cid) async {
    if (!_isConnected) {
      throw ConnectionException('Not connected', peer: peer);
    }

    await Future.delayed(Duration(milliseconds: 10 + Random().nextInt(30)));

    // Random chance that peer has the block
    return Random().nextDouble() < 0.6;
  }

  @override
  Future<Set<String>> getCapabilities() async {
    return {
      'chat_messages',
      'user_presence',
      'block_exchange',
      'merkle_dag_sync',
    };
  }

  @override
  Future<Duration> ping() async {
    if (!_isConnected) {
      throw ConnectionException('Not connected', peer: peer);
    }

    final start = DateTime.now();
    await Future.delayed(Duration(milliseconds: 20 + Random().nextInt(100)));
    return DateTime.now().difference(start);
  }
}
