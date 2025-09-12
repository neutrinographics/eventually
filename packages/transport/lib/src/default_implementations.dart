import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'interfaces.dart';
import 'models.dart';

/// A simple JSON-based handshake protocol
class JsonHandshakeProtocol implements HandshakeProtocol {
  const JsonHandshakeProtocol({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;

  @override
  Future<HandshakeResult> initiateHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  ) async {
    try {
      // Send handshake initiation
      final handshakeData = {
        'type': 'handshake_init',
        'peer_id': localPeerId.value,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'version': '1.0.0',
      };

      final jsonBytes = utf8.encode(json.encode(handshakeData));
      await connection.send(Uint8List.fromList(jsonBytes));

      // Wait for response
      final responseCompleter = Completer<Map<String, dynamic>>();
      late StreamSubscription<Uint8List> subscription;

      subscription = connection.dataReceived.listen((data) {
        try {
          final jsonString = utf8.decode(data);
          final response = json.decode(jsonString) as Map<String, dynamic>;
          subscription.cancel();
          responseCompleter.complete(response);
        } catch (e) {
          subscription.cancel();
          responseCompleter.completeError(e);
        }
      });

      final response = await responseCompleter.future.timeout(timeout);

      // Validate response
      if (response['type'] != 'handshake_response') {
        return const HandshakeResult(
          success: false,
          remotePeerId: null,
          error: 'Invalid handshake response type',
        );
      }

      final remotePeerIdString = response['peer_id'] as String?;
      if (remotePeerIdString == null) {
        return const HandshakeResult(
          success: false,
          remotePeerId: null,
          error: 'Missing peer ID in handshake response',
        );
      }

      return HandshakeResult(
        success: true,
        remotePeerId: PeerId(remotePeerIdString),
        metadata: {
          'version': response['version'],
          'timestamp': response['timestamp'],
        },
      );
    } catch (e) {
      return HandshakeResult(
        success: false,
        remotePeerId: null,
        error: e.toString(),
      );
    }
  }

  @override
  Future<HandshakeResult> respondToHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  ) async {
    try {
      // Wait for handshake initiation
      final initCompleter = Completer<Map<String, dynamic>>();
      late StreamSubscription<Uint8List> subscription;

      subscription = connection.dataReceived.listen((data) {
        try {
          final jsonString = utf8.decode(data);
          final init = json.decode(jsonString) as Map<String, dynamic>;
          subscription.cancel();
          initCompleter.complete(init);
        } catch (e) {
          subscription.cancel();
          initCompleter.completeError(e);
        }
      });

      final init = await initCompleter.future.timeout(timeout);

      // Validate initiation
      if (init['type'] != 'handshake_init') {
        return const HandshakeResult(
          success: false,
          remotePeerId: null,
          error: 'Invalid handshake initiation type',
        );
      }

      final remotePeerIdString = init['peer_id'] as String?;
      if (remotePeerIdString == null) {
        return const HandshakeResult(
          success: false,
          remotePeerId: null,
          error: 'Missing peer ID in handshake initiation',
        );
      }

      // Send response
      final responseData = {
        'type': 'handshake_response',
        'peer_id': localPeerId.value,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'version': '1.0.0',
      };

      final jsonBytes = utf8.encode(json.encode(responseData));
      await connection.send(Uint8List.fromList(jsonBytes));

      return HandshakeResult(
        success: true,
        remotePeerId: PeerId(remotePeerIdString),
        metadata: {'version': init['version'], 'timestamp': init['timestamp']},
      );
    } catch (e) {
      return HandshakeResult(
        success: false,
        remotePeerId: null,
        error: e.toString(),
      );
    }
  }
}

/// In-memory implementation of PeerStore
class InMemoryPeerStore implements PeerStore {
  InMemoryPeerStore() : _peers = <PeerId, Peer>{};

  final Map<PeerId, Peer> _peers;
  final StreamController<PeerStoreEvent> _updatesController =
      StreamController<PeerStoreEvent>.broadcast();

  @override
  Stream<PeerStoreEvent> get peerUpdates => _updatesController.stream;

  @override
  Future<void> storePeer(Peer peer) async {
    final existing = _peers[peer.id];
    _peers[peer.id] = peer;

    if (existing == null) {
      _updatesController.add(PeerAdded(peer));
    } else {
      _updatesController.add(PeerUpdated(peer));
    }
  }

  @override
  Future<void> removePeer(PeerId peerId) async {
    final peer = _peers.remove(peerId);
    if (peer != null) {
      _updatesController.add(PeerRemoved(peer));
    }
  }

  @override
  Future<Peer?> getPeer(PeerId peerId) async {
    return _peers[peerId];
  }

  @override
  Future<List<Peer>> getAllPeers() async {
    return _peers.values.toList();
  }

  /// Dispose of this store and close the updates stream
  Future<void> dispose() async {
    await _updatesController.close();
  }
}

/// A simple broadcast-based peer discovery mechanism
class BroadcastPeerDiscovery implements PeerDiscovery {
  BroadcastPeerDiscovery({
    required this.localPeerId,
    required this.broadcastInterval,
    this.peerTimeout = const Duration(minutes: 5),
  });

  final PeerId localPeerId;
  final Duration broadcastInterval;
  final Duration peerTimeout;

  final Map<PeerId, _DiscoveredPeerInfo> _discoveredPeers = {};
  final StreamController<Peer> _peersDiscoveredController =
      StreamController<Peer>.broadcast();
  final StreamController<Peer> _peersLostController =
      StreamController<Peer>.broadcast();

  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isDiscovering = false;

  @override
  Stream<Peer> get peersDiscovered => _peersDiscoveredController.stream;

  @override
  Stream<Peer> get peersLost => _peersLostController.stream;

  @override
  bool get isDiscovering => _isDiscovering;

  @override
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    // Start broadcasting our presence
    _broadcastTimer = Timer.periodic(broadcastInterval, (_) {
      _broadcastPresence();
    });

    // Start cleanup timer to remove stale peers
    _cleanupTimer = Timer.periodic(
      Duration(seconds: peerTimeout.inSeconds ~/ 2),
      (_) => _cleanupStalePeers(),
    );

    // Initial broadcast
    _broadcastPresence();
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;
    _isDiscovering = false;

    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer = null;

    // Clear discovered peers
    final peers = _discoveredPeers.values.map((info) => info.peer).toList();
    _discoveredPeers.clear();

    for (final peer in peers) {
      _peersLostController.add(peer);
    }
  }

  /// Simulate receiving a broadcast message from a peer
  /// In a real implementation, this would be called by the underlying
  /// transport when broadcast messages are received
  void simulateReceivedBroadcast({
    required PeerId peerId,
    required DeviceAddress address,
    Map<String, dynamic> metadata = const {},
  }) {
    if (!_isDiscovering || peerId == localPeerId) return;

    final now = DateTime.now();
    final existing = _discoveredPeers[peerId];

    if (existing == null) {
      // New peer discovered
      final peer = Peer(
        id: peerId,
        address: address,
        status: PeerStatus.discovered,
        metadata: metadata,
        lastSeen: now,
      );

      _discoveredPeers[peerId] = _DiscoveredPeerInfo(peer: peer, lastSeen: now);

      _peersDiscoveredController.add(peer);
    } else {
      // Update existing peer
      final updatedPeer = existing.peer.copyWith(
        address: address,
        metadata: metadata,
        lastSeen: now,
      );

      _discoveredPeers[peerId] = _DiscoveredPeerInfo(
        peer: updatedPeer,
        lastSeen: now,
      );

      _peersDiscoveredController.add(updatedPeer);
    }
  }

  /// Broadcast our presence (would be implemented by concrete transport)
  void _broadcastPresence() {
    // This is a placeholder - in a real implementation, this would
    // use the underlying transport to broadcast presence information
    // For example, UDP broadcast, mDNS, Bluetooth advertising, etc.
  }

  /// Remove peers that haven't been seen recently
  void _cleanupStalePeers() {
    final now = DateTime.now();
    final staleThreshold = now.subtract(peerTimeout);
    final stalePeers = <PeerId>[];

    for (final entry in _discoveredPeers.entries) {
      if (entry.value.lastSeen.isBefore(staleThreshold)) {
        stalePeers.add(entry.key);
      }
    }

    for (final peerId in stalePeers) {
      final info = _discoveredPeers.remove(peerId);
      if (info != null) {
        _peersLostController.add(info.peer);
      }
    }
  }

  /// Dispose of this discovery mechanism
  Future<void> dispose() async {
    await stopDiscovery();
    await _peersDiscoveredController.close();
    await _peersLostController.close();
  }
}

/// Internal class to track discovered peer information
class _DiscoveredPeerInfo {
  const _DiscoveredPeerInfo({required this.peer, required this.lastSeen});

  final Peer peer;
  final DateTime lastSeen;
}

/// A no-op peer discovery implementation
class NoOpPeerDiscovery implements PeerDiscovery {
  const NoOpPeerDiscovery();

  @override
  bool get isDiscovering => false;

  @override
  Stream<Peer> get peersDiscovered => const Stream.empty();

  @override
  Stream<Peer> get peersLost => const Stream.empty();

  @override
  Future<void> startDiscovery() async {}

  @override
  Future<void> stopDiscovery() async {}
}
