import 'dart:async';

import 'cid.dart';
import 'peer.dart';
import 'transport.dart';
import 'peer_config.dart';
import 'protocol.dart';
import 'block.dart';

/// Generic peer manager that doesn't own the transport layer.
///
/// This peer manager handles peer relationships and connections but delegates
/// network operations to a transport that is owned by the synchronizer.
/// The synchronizer orchestrates communication between this peer manager
/// and the transport layer.
class GenericPeerManager implements PeerManager {
  /// Configuration for this peer manager.
  final PeerConfig config;

  /// Default protocol for sync operations.
  final SyncProtocol syncProtocol;

  // Internal state
  final Map<PeerId, Peer> _peers = {};

  final Map<TransportDeviceAddress, PeerId> _transportToPeerIdMap = {};

  final StreamController<PeerEvent> _peerEventsController =
      StreamController<PeerEvent>.broadcast();
  final StreamController<OutgoingBytes> _outgoingBytesController =
      StreamController<OutgoingBytes>.broadcast();

  bool _isDisposed = false;

  /// Creates a new generic peer manager.
  GenericPeerManager({required this.config, SyncProtocol? syncProtocol})
    : syncProtocol = syncProtocol ?? BitSwapProtocol();

  @override
  Iterable<Peer> get connectedPeers => _peers.values.where((p) => p.isActive);

  @override
  Iterable<Peer> get peers => _peers.values;

  @override
  Stream<OutgoingBytes> get outgoingBytes => _outgoingBytesController.stream;

  @override
  Stream<PeerEvent> get peerEvents => _peerEventsController.stream;

  @override
  Future<void> handleIncomingBytes(IncomingBytes incomingBytes) async {
    try {
      final peerId = _transportToPeerIdMap[incomingBytes.device.address];
      if (peerId != null) {
        final peer = _peers[peerId];
        if (peer != null && peer.isActive) {
          final message =
              syncProtocol.decodeMessage(incomingBytes.bytes) as Message;
          await _handleProtocolMessage(peer, message);
        } else {
          // Handle potential handshake from unconnected peer
          await _handlePotentialHandshake(incomingBytes);
        }
      } else {
        // Unknown device - might be initial contact
        await _handlePotentialHandshake(incomingBytes);
      }
    } catch (e) {
      debugPrint(
        'Failed to process message from ${incomingBytes.device.address}: $e',
      );
    }
  }

  @override
  Future<Peer> registerDeviceAsPeer(
    TransportDevice device, {
    Duration? timeout = const Duration(seconds: 10),
  }) async {
    if (_isDisposed) throw Exception("PeerManager is disposed");

    // Check if a peer already exists
    final existingPeerId = _transportToPeerIdMap[device.address];
    if (existingPeerId != null && _peers.containsKey(existingPeerId)) {
      return _peers[existingPeerId]!;
    }

    // Create a new peer with a deterministic ID
    final peerId = PeerId('peer_${device.address.value.hashCode.abs()}');
    final peer = Peer(
      id: peerId,
      transportPeer: device,
      isActive: false, // Disconnected state initially
    );

    // Register the peer
    _peers[peerId] = peer;
    _transportToPeerIdMap[device.address] = peerId;

    // Emit discovery event
    _peerEventsController.add(
      PeerDiscovered(peer: peer, timestamp: DateTime.now()),
    );

    return peer;
  }

  @override
  Future<void> connectToPeer(PeerId peerId) async {
    if (_isDisposed) {
      throw PeerException('Peer manager is disposed');
    }

    final peer = _peers[peerId];
    if (peer == null) {
      throw PeerException('Unknown peer: $peerId');
    }

    if (peer.isActive) {
      return; // Already connected
    }

    // Update peer state to connected
    _peers[peerId] = peer.copyWith(isActive: true);

    // Emit connection event
    _peerEventsController.add(
      PeerConnected(peer: _peers[peerId]!, timestamp: DateTime.now()),
    );
  }

  @override
  @Deprecated('Cannot directly access peer connections')
  PeerConnection? getConnection(PeerId peerId) {
    // Connections are no longer exposed directly
    return null;
  }

  @override
  Future<void> disconnect(PeerId peerId) async {
    if (_isDisposed) return;

    final peer = _peers[peerId];

    if (peer?.transportPeer != null) {
      _transportToPeerIdMap.remove(peer!.transportPeer.address);
    }

    _peers.remove(peerId);

    if (peer != null) {
      _peerEventsController.add(
        PeerDisconnected(peer: peer, timestamp: DateTime.now()),
      );
    }
  }

  @override
  Future<void> disconnectAll() async {
    if (_isDisposed) return;

    final peerIds = _peers.keys.toList();
    for (final peerId in peerIds) {
      await disconnect(peerId);
    }
  }

  @override
  Future<List<Peer>> findPeersWithBlock(CID cid) async {
    if (_isDisposed) return [];

    final peersWithBlock = <Peer>[];

    for (final peer in connectedPeers) {
      // For now, assume all connected peers might have any block
      // In a full implementation, we'd track which blocks each peer has
      peersWithBlock.add(peer);
    }

    return peersWithBlock;
  }

  @override
  Future<void> broadcast(Message message) async {
    if (_isDisposed) return;

    final broadcastFutures = <Future>[];

    for (final peer in connectedPeers) {
      broadcastFutures.add(
        _sendMessageToPeer(peer, message).catchError(
          (e) => debugPrint('Failed to broadcast to ${peer.id}: $e'),
        ),
      );
    }

    await Future.wait(broadcastFutures);
  }

  @override
  Future<PeerStats> getStats() async {
    if (_isDisposed) {
      return PeerStats(
        totalPeers: 0,
        connectedPeers: 0,
        totalMessages: 0,
        totalBytesReceived: 0,
        totalBytesSent: 0,
      );
    }

    return PeerStats(
      totalPeers: _peers.length,
      connectedPeers: connectedPeers.length,
      totalMessages: 0,
      totalBytesReceived: 0,
      totalBytesSent: 0,
    );
  }

  /// Disposes of the peer manager and releases resources.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    await disconnectAll();
    await _peerEventsController.close();
    _transportToPeerIdMap.clear();
  }

  // Private helper methods

  Future<void> _handleProtocolMessage(Peer peer, Message message) async {
    // Handle different message types based on sync protocol
    switch (message.runtimeType) {
      case Have:
        await _handleHaveMessage(peer, message as Have);
        break;
      case Want:
        await _handleWantMessage(peer, message as Want);
        break;
      case Block:
        await _handleBlockMessage(peer, message as Block);
        break;
      default:
        debugPrint('Unknown message type: ${message.runtimeType}');
    }
  }

  Future<void> _handlePotentialHandshake(IncomingBytes incomingBytes) async {
    // For now, auto-register unknown devices as peers
    // In a full implementation, this would handle handshake protocol
    try {
      await registerDeviceAsPeer(incomingBytes.device);
    } catch (e) {
      debugPrint('Failed to register device: $e');
    }
  }

  Future<void> _handleHaveMessage(Peer peer, Have message) async {
    // Peer is announcing they have these blocks
    // Could request blocks we need
  }

  Future<void> _handleWantMessage(Peer peer, Want message) async {
    // Peer is requesting these blocks
    // Send blocks we have
  }

  Future<void> _handleBlockMessage(Peer peer, Block message) async {
    // Peer sent us a block
    // This would typically be handled by the synchronizer
  }

  Future<void> _sendMessageToPeer(Peer peer, Message message) async {
    if (!peer.isActive) return;

    try {
      final bytes = syncProtocol.encodeMessage(message as ProtocolMessage);
      final outgoing = OutgoingBytes(peer.transportPeer, bytes);
      _outgoingBytesController.add(outgoing);
    } catch (e) {
      throw PeerException('Failed to send message to ${peer.id}', cause: e);
    }
  }

  /// Debug print function for development.
  void debugPrint(String message) {
    print('[GenericPeerManager] $message');
  }
}
