import 'dart:async';
import 'dart:typed_data';

import 'interfaces.dart';
import 'models.dart';

/// Main class that orchestrates peer connections, discovery, and messaging
class TransportManager {
  TransportManager(this._config)
    : _peers = <PeerId, Peer>{},
      _connections = <PeerId, _PeerConnection>{},
      _peerUpdatesController = StreamController<Peer>.broadcast(),
      _messageController = StreamController<TransportMessage>.broadcast(),
      _connectionRequestController =
          StreamController<ConnectionRequest>.broadcast(),
      _connectionResultController =
          StreamController<ConnectionAttemptResult>.broadcast() {
    _initialize();
  }

  final TransportConfig _config;
  final Map<PeerId, Peer> _peers;
  final Map<PeerId, _PeerConnection> _connections;

  final StreamController<Peer> _peerUpdatesController;
  final StreamController<TransportMessage> _messageController;
  final StreamController<ConnectionRequest> _connectionRequestController;
  final StreamController<ConnectionAttemptResult> _connectionResultController;

  StreamSubscription<IncomingConnectionAttempt>? _incomingConnectionsSub;
  StreamSubscription<Peer>? _peersDiscoveredSub;
  StreamSubscription<Peer>? _peersLostSub;
  StreamSubscription<PeerStoreEvent>? _peerStoreSub;

  bool _isStarted = false;
  bool _isDisposed = false;

  /// Stream of peer updates (status changes, new peers, etc.)
  Stream<Peer> get peerUpdates => _peerUpdatesController.stream;

  /// Stream of received messages
  Stream<TransportMessage> get messagesReceived => _messageController.stream;

  /// Stream of incoming connection requests that need approval
  Stream<ConnectionRequest> get connectionRequests =>
      _connectionRequestController.stream;

  /// Stream of connection attempt results
  Stream<ConnectionAttemptResult> get connectionResults =>
      _connectionResultController.stream;

  /// Get all currently known peers
  List<Peer> get peers => _peers.values.toList();

  /// Get a specific peer by ID
  Peer? getPeer(PeerId peerId) => _peers[peerId];

  /// Whether the transport manager is currently started
  bool get isStarted => _isStarted;

  /// The local peer ID
  PeerId get localPeerId => _config.localPeerId;

  /// Initialize internal subscriptions
  void _initialize() {
    // Listen for incoming connections
    _incomingConnectionsSub = _config.protocol.incomingConnections.listen(
      _handleIncomingConnection,
    );

    // Set up peer discovery if available
    final discovery = _config.peerDiscovery;
    if (discovery != null) {
      _peersDiscoveredSub = discovery.peersDiscovered.listen(
        _handlePeerDiscovered,
      );
      _peersLostSub = discovery.peersLost.listen(_handlePeerLost);
    }

    // Set up peer store if available
    final store = _config.peerStore;
    if (store != null) {
      _peerStoreSub = store.peerUpdates.listen(_handlePeerStoreEvent);
    }
  }

  /// Start the transport manager
  Future<void> start({DeviceAddress? listenAddress}) async {
    if (_isStarted || _isDisposed) return;

    try {
      // Start listening for connections
      if (listenAddress != null) {
        await _config.protocol.startListening(listenAddress);
      }

      // Start peer discovery if available
      final discovery = _config.peerDiscovery;
      if (discovery != null) {
        await discovery.startDiscovery();
      }

      // Load existing peers from store
      final store = _config.peerStore;
      if (store != null) {
        final storedPeers = await store.getAllPeers();
        for (final peer in storedPeers) {
          _peers[peer.id] = peer;
        }
      }

      _isStarted = true;
    } catch (e) {
      await stop(); // Clean up on failure
      rethrow;
    }
  }

  /// Stop the transport manager
  Future<void> stop() async {
    if (!_isStarted || _isDisposed) return;

    _isStarted = false;

    // Disconnect all peers
    final disconnectFutures = _connections.values
        .map((conn) => conn.disconnect())
        .toList();
    await Future.wait(disconnectFutures);
    _connections.clear();

    // Stop peer discovery
    final discovery = _config.peerDiscovery;
    if (discovery != null && discovery.isDiscovering) {
      await discovery.stopDiscovery();
    }

    // Stop listening for connections
    if (_config.protocol.isListening) {
      await _config.protocol.stopListening();
    }
  }

  /// Dispose of the transport manager and clean up resources
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await stop();

    // Cancel subscriptions
    await _incomingConnectionsSub?.cancel();
    await _peersDiscoveredSub?.cancel();
    await _peersLostSub?.cancel();
    await _peerStoreSub?.cancel();

    // Close stream controllers
    await _peerUpdatesController.close();
    await _messageController.close();
    await _connectionRequestController.close();
    await _connectionResultController.close();
  }

  /// Attempt to connect to a peer
  Future<ConnectionAttemptResult> connectToPeer(PeerId peerId) async {
    if (!_isStarted || _isDisposed) {
      return ConnectionAttemptResult(
        peerId: peerId,
        result: ConnectionResult.failed,
        error: 'Transport manager not started',
      );
    }

    final peer = _peers[peerId];
    if (peer == null) {
      return ConnectionAttemptResult(
        peerId: peerId,
        result: ConnectionResult.failed,
        error: 'Peer not found',
      );
    }

    if (_connections.containsKey(peerId)) {
      final existing = _connections[peerId]!;
      if (existing.isConnected) {
        return ConnectionAttemptResult(
          peerId: peerId,
          result: ConnectionResult.success,
        );
      }
    }

    // Check connection limits
    if (_connections.length >= _config.maxConnections) {
      return ConnectionAttemptResult(
        peerId: peerId,
        result: ConnectionResult.failed,
        error: 'Maximum connections reached',
      );
    }

    try {
      // Update peer status
      await _updatePeerStatus(peerId, PeerStatus.connecting);

      // Establish transport connection
      final transportConnection = await _config.protocol
          .connect(peer.address)
          .timeout(_config.connectionTimeout);

      if (transportConnection == null) {
        await _updatePeerStatus(peerId, PeerStatus.failed);
        return ConnectionAttemptResult(
          peerId: peerId,
          result: ConnectionResult.failed,
          error: 'Transport connection failed',
        );
      }

      // Perform handshake
      final handshakeResult = await _config.handshakeProtocol
          .initiateHandshake(transportConnection, _config.localPeerId)
          .timeout(_config.handshakeTimeout);

      if (!handshakeResult.success) {
        await transportConnection.close();
        await _updatePeerStatus(peerId, PeerStatus.failed);
        return ConnectionAttemptResult(
          peerId: peerId,
          result: ConnectionResult.failed,
          error: handshakeResult.error ?? 'Handshake failed',
        );
      }

      // Verify peer ID matches
      if (handshakeResult.remotePeerId != peerId) {
        await transportConnection.close();
        await _updatePeerStatus(peerId, PeerStatus.failed);
        return ConnectionAttemptResult(
          peerId: peerId,
          result: ConnectionResult.failed,
          error: 'Peer ID mismatch',
        );
      }

      // Create peer connection wrapper
      final peerConnection = _PeerConnection(
        peerId: peerId,
        connection: transportConnection,
        onMessage: _handleMessage,
        onDisconnect: () => _handlePeerDisconnected(peerId),
        localPeerId: _config.localPeerId,
      );

      _connections[peerId] = peerConnection;
      await _updatePeerStatus(peerId, PeerStatus.connected);

      final result = ConnectionAttemptResult(
        peerId: peerId,
        result: ConnectionResult.success,
        metadata: handshakeResult.metadata,
      );

      _connectionResultController.add(result);
      return result;
    } on TimeoutException {
      await _updatePeerStatus(peerId, PeerStatus.failed);
      final result = ConnectionAttemptResult(
        peerId: peerId,
        result: ConnectionResult.timeout,
        error: 'Connection timeout',
      );
      _connectionResultController.add(result);
      return result;
    } catch (e) {
      await _updatePeerStatus(peerId, PeerStatus.failed);
      final result = ConnectionAttemptResult(
        peerId: peerId,
        result: ConnectionResult.failed,
        error: e.toString(),
      );
      _connectionResultController.add(result);
      return result;
    }
  }

  /// Disconnect from a peer
  Future<void> disconnectFromPeer(PeerId peerId) async {
    final connection = _connections[peerId];
    if (connection != null) {
      await _updatePeerStatus(peerId, PeerStatus.disconnecting);
      await connection.disconnect();
      _connections.remove(peerId);
      await _updatePeerStatus(peerId, PeerStatus.disconnected);
    }
  }

  /// Send a message to a peer
  Future<bool> sendMessage(TransportMessage message) async {
    if (!_isStarted || _isDisposed) return false;

    final connection = _connections[message.recipientId];
    if (connection == null || !connection.isConnected) {
      return false;
    }

    try {
      await connection.sendMessage(message);
      return true;
    } catch (e) {
      // Connection might have failed, handle disconnection
      await _handlePeerDisconnected(message.recipientId);
      return false;
    }
  }

  /// Handle incoming connection attempts
  Future<void> _handleIncomingConnection(
    IncomingConnectionAttempt attempt,
  ) async {
    if (!_isStarted || _isDisposed) {
      await attempt.connection.close();
      return;
    }

    try {
      // Perform handshake as responder
      final handshakeResult = await _config.handshakeProtocol
          .respondToHandshake(attempt.connection, _config.localPeerId)
          .timeout(_config.handshakeTimeout);

      if (!handshakeResult.success || handshakeResult.remotePeerId == null) {
        await attempt.connection.close();
        return;
      }

      final remotePeerId = handshakeResult.remotePeerId!;

      // Create connection request
      final request = ConnectionRequest(
        peerId: remotePeerId,
        address: attempt.address,
        timestamp: DateTime.now(),
        metadata: handshakeResult.metadata,
      );

      // Check if we should auto-approve or request manual approval
      final response = await _config.approvalHandler.handleConnectionRequest(
        request,
      );

      if (response == ConnectionRequestResponse.reject) {
        await attempt.connection.close();
        return;
      }

      // Check connection limits
      if (_connections.length >= _config.maxConnections) {
        await attempt.connection.close();
        return;
      }

      // Accept the connection
      final peerConnection = _PeerConnection(
        peerId: remotePeerId,
        connection: attempt.connection,
        onMessage: _handleMessage,
        onDisconnect: () => _handlePeerDisconnected(remotePeerId),
        localPeerId: _config.localPeerId,
      );

      _connections[remotePeerId] = peerConnection;

      // Update or create peer record
      final existingPeer = _peers[remotePeerId];
      final peer =
          existingPeer?.copyWith(
            status: PeerStatus.connected,
            lastSeen: DateTime.now(),
          ) ??
          Peer(
            id: remotePeerId,
            address: attempt.address,
            status: PeerStatus.connected,
            lastSeen: DateTime.now(),
          );

      await _updatePeer(peer);

      // Emit connection request event (even if auto-approved)
      _connectionRequestController.add(request);
    } catch (e) {
      await attempt.connection.close();
    }
  }

  /// Handle discovered peers
  void _handlePeerDiscovered(Peer peer) {
    _updatePeer(peer);
  }

  /// Handle lost peers
  void _handlePeerLost(Peer peer) {
    final updatedPeer = peer.copyWith(status: PeerStatus.disconnected);
    _updatePeer(updatedPeer);
  }

  /// Handle peer store events
  void _handlePeerStoreEvent(PeerStoreEvent event) {
    switch (event) {
      case PeerAdded(:final peer):
      case PeerUpdated(:final peer):
        _peers[peer.id] = peer;
        _peerUpdatesController.add(peer);
      case PeerRemoved(:final peer):
        _peers.remove(peer.id);
        _peerUpdatesController.add(peer);
    }
  }

  /// Handle received messages
  void _handleMessage(TransportMessage message) {
    _messageController.add(message);
  }

  /// Handle peer disconnection
  Future<void> _handlePeerDisconnected(PeerId peerId) async {
    _connections.remove(peerId);
    await _updatePeerStatus(peerId, PeerStatus.disconnected);
  }

  /// Update peer information
  Future<void> _updatePeer(Peer peer) async {
    _peers[peer.id] = peer;
    _peerUpdatesController.add(peer);

    // Store in persistent store if available
    final store = _config.peerStore;
    if (store != null) {
      await store.storePeer(peer);
    }
  }

  /// Update peer status
  Future<void> _updatePeerStatus(PeerId peerId, PeerStatus status) async {
    final peer = _peers[peerId];
    if (peer != null) {
      final updatedPeer = peer.copyWith(
        status: status,
        lastSeen: DateTime.now(),
      );
      await _updatePeer(updatedPeer);
    }
  }
}

/// Internal wrapper for managing a peer connection
class _PeerConnection {
  _PeerConnection({
    required this.peerId,
    required this.connection,
    required this.onMessage,
    required this.onDisconnect,
    required this.localPeerId,
  }) {
    // Listen for incoming data
    _dataSubscription = connection.dataReceived.listen(
      _handleIncomingData,
      onError: (_) => disconnect(),
    );

    // Listen for connection close
    _closeSubscription = connection.connectionClosed.listen(
      (_) => disconnect(),
    );
  }

  final PeerId peerId;
  final TransportConnection connection;
  final void Function(TransportMessage) onMessage;
  final void Function() onDisconnect;
  final PeerId localPeerId;

  StreamSubscription<Uint8List>? _dataSubscription;
  StreamSubscription<void>? _closeSubscription;
  bool _isDisconnected = false;

  bool get isConnected => connection.isOpen && !_isDisconnected;

  /// Send a message over this connection
  Future<void> sendMessage(TransportMessage message) async {
    if (!isConnected) throw StateError('Connection is not open');

    // Simple message format: [messageId length][messageId][data]
    final messageIdBytes = (message.messageId ?? '').codeUnits;
    final messageIdLength = messageIdBytes.length;
    final data = Uint8List(4 + messageIdLength + message.data.length);

    // Write message ID length (4 bytes)
    data.buffer.asByteData().setUint32(0, messageIdLength, Endian.big);

    // Write message ID
    data.setRange(4, 4 + messageIdLength, messageIdBytes);

    // Write message data
    data.setRange(4 + messageIdLength, data.length, message.data);

    await connection.send(data);
  }

  /// Disconnect this connection
  Future<void> disconnect() async {
    if (_isDisconnected) return;
    _isDisconnected = true;

    await _dataSubscription?.cancel();
    await _closeSubscription?.cancel();

    if (connection.isOpen) {
      await connection.close();
    }

    onDisconnect();
  }

  /// Handle incoming raw data and convert to messages
  void _handleIncomingData(Uint8List data) {
    try {
      // Parse message format: [messageId length][messageId][data]
      if (data.length < 4) return;

      final messageIdLength = data.buffer.asByteData().getUint32(0, Endian.big);
      if (data.length < 4 + messageIdLength) return;

      final messageIdBytes = data.sublist(4, 4 + messageIdLength);
      final messageId = String.fromCharCodes(messageIdBytes);
      final messageData = data.sublist(4 + messageIdLength);

      final message = TransportMessage(
        senderId: peerId,
        recipientId: localPeerId,
        data: messageData,
        timestamp: DateTime.now(),
        messageId: messageId.isEmpty ? null : messageId,
      );

      onMessage(message);
    } catch (e) {
      // Ignore malformed messages
    }
  }
}
