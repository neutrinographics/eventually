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

/// A simple broadcast-based device discovery mechanism
class BroadcastDeviceDiscovery implements DeviceDiscovery {
  BroadcastDeviceDiscovery({
    required this.localDisplayName,
    required this.broadcastInterval,
    this.deviceTimeout = const Duration(minutes: 5),
  });

  final String localDisplayName;
  final Duration broadcastInterval;
  final Duration deviceTimeout;

  final Map<DeviceAddress, _DiscoveredDeviceInfo> _discoveredDevices = {};
  final StreamController<DiscoveredDevice> _devicesDiscoveredController =
      StreamController<DiscoveredDevice>.broadcast();
  final StreamController<DiscoveredDevice> _devicesLostController =
      StreamController<DiscoveredDevice>.broadcast();

  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isDiscovering = false;

  @override
  Stream<DiscoveredDevice> get devicesDiscovered =>
      _devicesDiscoveredController.stream;

  @override
  Stream<DiscoveredDevice> get devicesLost => _devicesLostController.stream;

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

    // Start cleanup timer to remove stale devices
    _cleanupTimer = Timer.periodic(
      Duration(seconds: deviceTimeout.inSeconds ~/ 2),
      (_) => _cleanupStaleDevices(),
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

    // Clear discovered devices
    final devices = _discoveredDevices.values
        .map((info) => info.device)
        .toList();
    _discoveredDevices.clear();

    for (final device in devices) {
      _devicesLostController.add(device);
    }
  }

  /// Simulate receiving a broadcast message from a device
  /// In a real implementation, this would be called by the underlying
  /// transport when broadcast messages are received
  void simulateReceivedBroadcast({
    required DeviceAddress address,
    required String displayName,
    Map<String, dynamic> metadata = const {},
  }) {
    if (!_isDiscovering) return;

    final now = DateTime.now();
    final existing = _discoveredDevices[address];

    if (existing == null) {
      // New device discovered
      final device = DiscoveredDevice(
        address: address,
        displayName: displayName,
        discoveredAt: now,
        metadata: metadata,
      );

      _discoveredDevices[address] = _DiscoveredDeviceInfo(
        device: device,
        lastSeen: now,
      );

      _devicesDiscoveredController.add(device);
    } else {
      // Update existing device
      final updatedDevice = DiscoveredDevice(
        address: address,
        displayName: displayName,
        discoveredAt: existing.device.discoveredAt,
        metadata: metadata,
      );

      _discoveredDevices[address] = _DiscoveredDeviceInfo(
        device: updatedDevice,
        lastSeen: now,
      );

      _devicesDiscoveredController.add(updatedDevice);
    }
  }

  /// Broadcast our presence (would be implemented by concrete transport)
  void _broadcastPresence() {
    // This is a placeholder - in a real implementation, this would
    // use the underlying transport to broadcast presence information
    // For example, UDP broadcast, mDNS, Bluetooth advertising, etc.
  }

  /// Remove devices that haven't been seen recently
  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final staleThreshold = now.subtract(deviceTimeout);
    final staleAddresses = <DeviceAddress>[];

    for (final entry in _discoveredDevices.entries) {
      if (entry.value.lastSeen.isBefore(staleThreshold)) {
        staleAddresses.add(entry.key);
      }
    }

    for (final address in staleAddresses) {
      final info = _discoveredDevices.remove(address);
      if (info != null) {
        _devicesLostController.add(info.device);
      }
    }
  }

  /// Dispose of this discovery mechanism
  Future<void> dispose() async {
    await stopDiscovery();
    await _devicesDiscoveredController.close();
    await _devicesLostController.close();
  }
}

/// Internal class to track discovered device information
class _DiscoveredDeviceInfo {
  const _DiscoveredDeviceInfo({required this.device, required this.lastSeen});

  final DiscoveredDevice device;
  final DateTime lastSeen;
}
