import 'dart:async';
import 'dart:typed_data';

import 'interfaces.dart';
import 'models.dart';

/// A transport manager that periodically discovers connected transport devices
/// and performs handshakes to establish peer relationships
class TransportManager {
  TransportManager(this._config) {
    _initialize();
  }

  final TransportConfig _config;

  // Stream controllers for public API
  final StreamController<Peer> _peerUpdatesController =
      StreamController<Peer>.broadcast();
  final StreamController<TransportMessage> _messageController =
      StreamController<TransportMessage>.broadcast();

  // Internal state
  final Map<PeerId, Peer> _peers = {};
  final Map<String, PendingHandshake> _pendingHandshakes = {};
  final Set<DeviceAddress> _knownTransportDevices = {};

  StreamSubscription<IncomingData>? _incomingDataSub;
  Timer? _discoveryTimer;

  bool _isStarted = false;
  bool _isDisposed = false;

  /// Stream of peer updates (added, status changed, removed)
  Stream<Peer> get peerUpdates => _peerUpdatesController.stream;

  /// Stream of messages received from peers
  Stream<TransportMessage> get messagesReceived => _messageController.stream;

  /// Get current peers
  List<Peer> get peers => _peers.values.toList();

  /// Get a specific peer by ID
  Peer? getPeer(PeerId peerId) => _peers[peerId];

  /// Whether the transport manager is started
  bool get isStarted => _isStarted;

  /// Local peer ID
  PeerId get localPeerId => _config.localPeerId;

  /// Discovery interval
  Duration get discoveryInterval => _config.discoveryInterval;

  void _initialize() {
    // Listen for incoming data
    _incomingDataSub = _config.protocol.incomingData.listen(
      _handleIncomingData,
    );
  }

  /// Start the transport manager
  Future<void> start() async {
    if (_isStarted || _isDisposed) return;

    try {
      // Initialize the transport protocol
      await _config.protocol.initialize();

      // Load existing peers from store
      final store = _config.peerStore;
      if (store != null) {
        final storedPeers = await store.getAllPeers();
        for (final peer in storedPeers) {
          _peers[peer.id] = peer;
          _peerUpdatesController.add(peer);
        }
      }

      // Start periodic device discovery
      _startPeriodicDiscovery();

      _isStarted = true;
    } catch (e) {
      await stop();
      rethrow;
    }
  }

  /// Stop the transport manager
  Future<void> stop() async {
    if (!_isStarted || _isDisposed) return;
    _isStarted = false;

    // Stop periodic discovery
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    // Shutdown transport protocol
    try {
      await _config.protocol.shutdown();
    } catch (e) {
      print('❌ Error shutting down transport protocol: $e');
    }

    // Clear state
    _pendingHandshakes.clear();
    _knownTransportDevices.clear();

    // Update all peers to disconnected
    for (final peer in _peers.values) {
      if (peer.status == PeerStatus.connected) {
        _updatePeerStatus(peer.id, PeerStatus.disconnected);
      }
    }
  }

  /// Dispose of the transport manager
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await stop();

    // Cancel subscriptions
    await _incomingDataSub?.cancel();

    // Close controllers
    await _peerUpdatesController.close();
    await _messageController.close();
  }

  /// Send a message to a peer
  Future<bool> sendMessage(TransportMessage message) async {
    if (!_isStarted || _isDisposed) return false;

    final peer = _peers[message.recipientId];
    if (peer == null || peer.status != PeerStatus.connected) {
      return false;
    }

    try {
      // Serialize message with protocol marker
      final messageData = _serializeMessage(message);

      // Send directly to peer's address
      await _config.protocol.sendData(peer.address, messageData);
      return true;
    } catch (e) {
      print('❌ Failed to send message to ${message.recipientId.value}: $e');
      return false;
    }
  }

  void _startPeriodicDiscovery() {
    // Do initial discovery
    _performDiscovery();

    // Set up periodic discovery
    _discoveryTimer = Timer.periodic(discoveryInterval, (_) {
      _performDiscovery();
    });
  }

  Future<void> _performDiscovery() async {
    if (!_isStarted || _isDisposed) return;

    try {
      final transportDevices = await _config.protocol.discoverDevices();

      for (final device in transportDevices) {
        // Check if this is a new device we haven't seen before
        if (!_knownTransportDevices.contains(device.address)) {
          _knownTransportDevices.add(device.address);

          // Check if we already have a peer for this address
          if (_findPeerByAddress(device.address) == null) {
            // No peer exists, initiate handshake
            _initiateHandshakeWithDevice(device);
          }
        }
      }

      // Remove devices that are no longer available
      final currentAddresses = transportDevices.map((d) => d.address).toSet();
      final removedAddresses = _knownTransportDevices.difference(
        currentAddresses,
      );

      for (final removedAddress in removedAddresses) {
        _knownTransportDevices.remove(removedAddress);
        final peerId = _findPeerByAddress(removedAddress);
        if (peerId != null) {
          _updatePeerStatus(peerId, PeerStatus.disconnected);
        }
      }
    } catch (e) {
      print('❌ Device discovery failed: $e');
    }
  }

  Future<void> _initiateHandshakeWithDevice(TransportDevice device) async {
    await _initiateHandshakeWithAddress(device.address);
    print(
      '🤝 Initiated handshake with ${device.displayName} (${device.address.value})',
    );
  }

  Future<void> _initiateHandshakeWithAddress(DeviceAddress address) async {
    try {
      // Create handshake ID for tracking
      final handshakeId =
          '${address.value}-${DateTime.now().millisecondsSinceEpoch}';

      // Store pending handshake
      final pending = PendingHandshake(
        id: handshakeId,
        address: address,
        isInitiator: true,
        timestamp: DateTime.now(),
      );
      _pendingHandshakes[handshakeId] = pending;

      // Initiate handshake
      final handshakeData = await _config.handshakeProtocol.initiateHandshake(
        _config.localPeerId,
      );

      // Mark handshake data
      final markedData = _markAsHandshake(handshakeData, handshakeId);

      // Send handshake
      await _config.protocol.sendData(address, markedData);

      // Set up timeout
      Timer(_config.handshakeTimeout, () {
        final pendingHandshake = _pendingHandshakes.remove(handshakeId);
        if (pendingHandshake != null) {
          print('⏰ Handshake timeout with ${address.value}');
        }
      });

      print('🤝 Initiated handshake with ${address.value}');
    } catch (e) {
      print('❌ Failed to initiate handshake with ${address.value}: $e');
    }
  }

  /// Handle incoming data from the transport protocol
  void _handleIncomingData(IncomingData incomingData) {
    // Check if this is handshake data or regular message data
    if (_isHandshakeData(incomingData.data)) {
      _handleHandshakeData(incomingData);
    } else {
      _handleMessageData(incomingData);
    }
  }

  /// Handle handshake data
  void _handleHandshakeData(IncomingData incomingData) async {
    try {
      final handshakeInfo = _extractHandshakeData(incomingData.data);
      final isResponse = handshakeInfo['is_response'] as bool;
      final handshakeId = handshakeInfo['handshake_id'] as String?;
      final actualData = handshakeInfo['data'] as Uint8List;

      if (isResponse && handshakeId != null) {
        // This is a handshake response
        final pending = _pendingHandshakes.remove(handshakeId);
        if (pending != null) {
          final result = await _config.handshakeProtocol
              .processHandshakeResponse(
                actualData,
                incomingData.fromAddress,
                _config.localPeerId,
              );

          if (result.success && result.remotePeerId != null) {
            _createPeer(
              result.remotePeerId!,
              incomingData.fromAddress,
              result.metadata,
            );
          }
        }
      } else {
        // This is an incoming handshake request
        final result = await _config.handshakeProtocol.handleIncomingHandshake(
          actualData,
          incomingData.fromAddress,
          _config.localPeerId,
        );

        if (result.success && result.remotePeerId != null) {
          final remotePeerId = result.remotePeerId!;

          // Auto-accept all connections in the new design
          _createPeer(remotePeerId, incomingData.fromAddress, result.metadata);

          // Send response if provided
          final responseData = result.metadata['response_data'] as Uint8List?;
          if (responseData != null && handshakeId != null) {
            final markedResponse = _markAsHandshakeResponse(
              responseData,
              handshakeId,
            );
            try {
              await _config.protocol.sendData(
                incomingData.fromAddress,
                markedResponse,
              );
            } catch (e) {
              print('❌ Failed to send handshake response: $e');
            }
          }
        }
      }
    } catch (e) {
      print('❌ Handshake error: $e');
    }
  }

  /// Handle regular message data
  void _handleMessageData(IncomingData incomingData) {
    try {
      final message = _deserializeMessage(incomingData);
      if (message != null) {
        _messageController.add(message);
      }
    } catch (e) {
      print('❌ Message deserialization error: $e');
    }
  }

  /// Create a new peer
  void _createPeer(
    PeerId peerId,
    DeviceAddress address,
    Map<String, dynamic> metadata,
  ) {
    final peer = Peer(
      id: peerId,
      address: address,
      status: PeerStatus.connected,
      lastSeen: DateTime.now(),
      metadata: metadata,
    );

    _peers[peerId] = peer;
    _peerUpdatesController.add(peer);

    // Store peer if store is available
    final store = _config.peerStore;
    if (store != null) {
      store.storePeer(peer);
    }

    print('🎉 Created peer: ${peerId.value} at ${address.value}');
  }

  /// Update peer status
  void _updatePeerStatus(PeerId peerId, PeerStatus status) {
    final peer = _peers[peerId];
    if (peer != null && peer.status != status) {
      final updatedPeer = peer.copyWith(
        status: status,
        lastSeen: DateTime.now(),
      );
      _peers[peerId] = updatedPeer;
      _peerUpdatesController.add(updatedPeer);

      // Update in store if available
      final store = _config.peerStore;
      if (store != null) {
        store.storePeer(updatedPeer);
      }

      print('📊 Updated peer ${peerId.value} status: $status');
    }
  }

  /// Find peer ID by address
  PeerId? _findPeerByAddress(DeviceAddress address) {
    for (final peer in _peers.values) {
      if (peer.address.value == address.value) {
        return peer.id;
      }
    }
    return null;
  }

  /// Check if incoming data is handshake data
  bool _isHandshakeData(Uint8List data) {
    if (data.length < 4) return false;
    // Check for handshake marker
    return data[0] == 0x48 && data[1] == 0x53 && data[2] == 0x4B;
  }

  /// Mark data as handshake
  Uint8List _markAsHandshake(Uint8List data, String handshakeId) {
    final idBytes = Uint8List.fromList(handshakeId.codeUnits);
    final result = Uint8List(
      3 + 1 + idBytes.length + 1 + data.length,
    ); // +1 for null terminator
    result[0] = 0x48; // Handshake marker 'H'
    result[1] = 0x53; // 'S'
    result[2] = 0x4B; // 'K'
    result[3] = 0x00; // Request flag
    result.setRange(4, 4 + idBytes.length, idBytes);
    result[4 + idBytes.length] = 0x00; // Null terminator
    result.setRange(4 + idBytes.length + 1, result.length, data);
    return result;
  }

  /// Mark data as handshake response
  Uint8List _markAsHandshakeResponse(Uint8List data, String handshakeId) {
    final idBytes = Uint8List.fromList(handshakeId.codeUnits);
    final result = Uint8List(
      3 + 1 + idBytes.length + 1 + data.length,
    ); // +1 for null terminator
    result[0] = 0x48; // Handshake marker 'H'
    result[1] = 0x53; // 'S'
    result[2] = 0x4B; // 'K'
    result[3] = 0x01; // Response flag
    result.setRange(4, 4 + idBytes.length, idBytes);
    result[4 + idBytes.length] = 0x00; // Null terminator
    result.setRange(4 + idBytes.length + 1, result.length, data);
    return result;
  }

  /// Extract handshake data and metadata
  Map<String, dynamic> _extractHandshakeData(Uint8List data) {
    final isResponse = data[3] == 0x01;

    // Find the handshake ID (null-terminated)
    var idEnd = 4;
    while (idEnd < data.length && data[idEnd] != 0) {
      idEnd++;
    }

    final handshakeId = String.fromCharCodes(data.sublist(4, idEnd));
    final actualData = data.sublist(idEnd + 1);

    return {
      'is_response': isResponse,
      'handshake_id': handshakeId,
      'data': actualData,
    };
  }

  /// Serialize a message for transmission
  Uint8List _serializeMessage(TransportMessage message) {
    final senderBytes = Uint8List.fromList(message.senderId.value.codeUnits);
    final recipientBytes = Uint8List.fromList(
      message.recipientId.value.codeUnits,
    );
    final timestampBytes = Uint8List(8)
      ..buffer.asByteData().setInt64(
        0,
        message.timestamp.millisecondsSinceEpoch,
      );

    final result = Uint8List(
      3 +
          1 +
          1 +
          senderBytes.length +
          1 +
          recipientBytes.length +
          8 +
          message.data.length,
    );
    var offset = 0;

    // Message marker
    result[offset++] = 0x4D; // 'M'
    result[offset++] = 0x53; // 'S'
    result[offset++] = 0x47; // 'G'

    // Sender ID length and data
    result[offset++] = senderBytes.length;
    result.setRange(offset, offset + senderBytes.length, senderBytes);
    offset += senderBytes.length;

    // Recipient ID length and data
    result[offset++] = recipientBytes.length;
    result.setRange(offset, offset + recipientBytes.length, recipientBytes);
    offset += recipientBytes.length;

    // Timestamp
    result.setRange(offset, offset + 8, timestampBytes);
    offset += 8;

    // Message data
    result.setRange(offset, result.length, message.data);

    return result;
  }

  /// Deserialize incoming data to a message
  TransportMessage? _deserializeMessage(IncomingData incomingData) {
    try {
      final data = incomingData.data;
      if (data.length < 3 ||
          data[0] != 0x4D ||
          data[1] != 0x53 ||
          data[2] != 0x47) {
        return null; // Not a message
      }

      var offset = 3;

      // Read sender ID
      final senderLength = data[offset++];
      final senderBytes = data.sublist(offset, offset + senderLength);
      offset += senderLength;
      final senderId = PeerId(String.fromCharCodes(senderBytes));

      // Read recipient ID
      final recipientLength = data[offset++];
      final recipientBytes = data.sublist(offset, offset + recipientLength);
      offset += recipientLength;
      final recipientId = PeerId(String.fromCharCodes(recipientBytes));

      // Read timestamp
      final timestampMs = data.buffer.asByteData().getInt64(offset);
      offset += 8;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);

      // Read message data
      final messageData = data.sublist(offset);

      return TransportMessage(
        senderId: senderId,
        recipientId: recipientId,
        data: messageData,
        timestamp: timestamp,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Information about a pending handshake
class PendingHandshake {
  PendingHandshake({
    required this.id,
    required this.address,
    required this.isInitiator,
    required this.timestamp,
  });

  final String id;
  final DeviceAddress address;
  final bool isInitiator;
  final DateTime timestamp;
}
