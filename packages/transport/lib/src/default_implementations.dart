import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'interfaces.dart';
import 'models.dart';

/// A simple JSON-based handshake protocol for the new direct transmission model
class JsonHandshakeProtocol implements HandshakeProtocol {
  const JsonHandshakeProtocol();

  @override
  Future<Uint8List> initiateHandshake(PeerId localPeerId) async {
    // Create handshake initiation data
    final handshakeData = {
      'type': 'handshake_init',
      'peer_id': localPeerId.value,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'version': '1.0.0',
    };

    final jsonBytes = utf8.encode(json.encode(handshakeData));
    return Uint8List.fromList(jsonBytes);
  }

  @override
  Future<HandshakeResult> handleIncomingHandshake(
    Uint8List handshakeData,
    DeviceAddress fromAddress,
    PeerId localPeerId,
  ) async {
    try {
      final jsonString = utf8.decode(handshakeData);
      final request = json.decode(jsonString) as Map<String, dynamic>;

      // Validate request
      if (request['type'] != 'handshake_init') {
        return const HandshakeResult(
          success: false,
          remotePeerId: null,
          error: 'Invalid handshake request type',
        );
      }

      final remotePeerIdValue = request['peer_id'] as String?;
      if (remotePeerIdValue == null) {
        return const HandshakeResult(
          success: false,
          remotePeerId: null,
          error: 'Remote peer ID not provided in handshake',
        );
      }

      final remotePeerId = PeerId(remotePeerIdValue);

      // Create handshake response data
      final responseData = {
        'type': 'handshake_response',
        'peer_id': localPeerId.value,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'version': '1.0.0',
      };

      final responseBytes = utf8.encode(json.encode(responseData));

      return HandshakeResult(
        success: true,
        remotePeerId: remotePeerId,
        metadata: {'response_data': Uint8List.fromList(responseBytes)},
      );
    } catch (e) {
      return HandshakeResult(
        success: false,
        remotePeerId: null,
        error: 'Failed to process handshake: $e',
      );
    }
  }

  @override
  Future<HandshakeResult> processHandshakeResponse(
    Uint8List responseData,
    DeviceAddress fromAddress,
    PeerId localPeerId,
  ) async {
    try {
      final jsonString = utf8.decode(responseData);
      final response = json.decode(jsonString) as Map<String, dynamic>;

      // Validate response
      if (response['type'] != 'handshake_response') {
        return const HandshakeResult(
          success: false,
          remotePeerId: null,
          error: 'Invalid handshake response type',
        );
      }

      final remotePeerIdValue = response['peer_id'] as String?;
      if (remotePeerIdValue == null) {
        return const HandshakeResult(
          success: false,
          remotePeerId: null,
          error: 'Remote peer ID not provided in response',
        );
      }

      return HandshakeResult(
        success: true,
        remotePeerId: PeerId(remotePeerIdValue),
      );
    } catch (e) {
      return HandshakeResult(
        success: false,
        remotePeerId: null,
        error: 'Failed to process handshake response: $e',
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

/// A simple broadcast-based device discovery mechanism
