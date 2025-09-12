import 'dart:async';
import 'dart:typed_data';

import 'package:transport/transport.dart';

/// A simple in-memory transport protocol for demonstration purposes
class InMemoryTransportProtocol implements TransportProtocol {
  InMemoryTransportProtocol(this.address) {
    _incomingController =
        StreamController<IncomingConnectionAttempt>.broadcast();
    _devicesDiscoveredController =
        StreamController<DiscoveredDevice>.broadcast();
    _devicesLostController = StreamController<DeviceAddress>.broadcast();
  }

  static final Map<String, InMemoryTransportProtocol> _instances = {};
  static final Map<String, StreamController<IncomingConnectionAttempt>>
  _listeners = {};

  final DeviceAddress address;
  bool _isListening = false;
  bool _isDiscovering = false;
  late final StreamController<IncomingConnectionAttempt> _incomingController;
  late final StreamController<DiscoveredDevice> _devicesDiscoveredController;
  late final StreamController<DeviceAddress> _devicesLostController;

  @override
  bool get isListening => _isListening;

  @override
  bool get isDiscovering => _isDiscovering;

  @override
  Stream<IncomingConnectionAttempt> get incomingConnections {
    return _incomingController.stream;
  }

  @override
  Stream<DiscoveredDevice> get devicesDiscovered =>
      _devicesDiscoveredController.stream;

  @override
  Stream<DeviceAddress> get devicesLost => _devicesLostController.stream;

  @override
  Future<void> startListening() async {
    if (_isListening) return;

    _instances[address.value] = this;
    _listeners[address.value] = _incomingController;
    _isListening = true;
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening) return;

    _instances.remove(address.value);
    await _listeners[address.value]?.close();
    _listeners.remove(address.value);
    _isListening = false;
  }

  @override
  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    // Simulate discovery by emitting existing instances
    for (final instanceAddress in _instances.keys) {
      if (instanceAddress != address.value) {
        final device = DiscoveredDevice(
          address: DeviceAddress(instanceAddress),
          displayName: 'InMemory Device ($instanceAddress)',
          discoveredAt: DateTime.now(),
          metadata: {},
        );
        _devicesDiscoveredController.add(device);
      }
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;
    _isDiscovering = false;
  }

  @override
  Future<TransportConnection?> connect(DeviceAddress targetAddress) async {
    final target = _instances[targetAddress.value];
    final listener = _listeners[targetAddress.value];

    if (target == null || listener == null) {
      return null; // Target not listening
    }

    // Create connection pair
    final localConnection = InMemoryTransportConnection(
      remoteAddress: targetAddress,
    );
    final remoteConnection = InMemoryTransportConnection(
      remoteAddress: address,
    );

    // Connect them
    localConnection._connectTo(remoteConnection);
    remoteConnection._connectTo(localConnection);

    // Notify the listener
    final attempt = IncomingConnectionAttempt(
      connection: remoteConnection,
      address: address,
    );
    listener.add(attempt);

    return localConnection;
  }

  /// Simulate receiving a broadcast for device discovery
  void simulateReceivedBroadcast({
    required DeviceAddress address,
    required String displayName,
  }) {
    if (_isDiscovering) {
      final device = DiscoveredDevice(
        address: address,
        displayName: displayName,
        discoveredAt: DateTime.now(),
        metadata: {},
      );
      _devicesDiscoveredController.add(device);
    }
  }

  /// Simulate a device going offline
  void simulateDeviceLost({
    required DeviceAddress address,
    required String displayName,
  }) {
    if (_isDiscovering) {
      _devicesLostController.add(address);
    }
  }
}

/// In-memory transport connection implementation
class InMemoryTransportConnection implements TransportConnection {
  InMemoryTransportConnection({required this.remoteAddress});

  @override
  final DeviceAddress remoteAddress;

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>();
  final StreamController<void> _closedController = StreamController<void>();

  InMemoryTransportConnection? _peer;
  bool _isOpen = true;

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<Uint8List> get dataReceived => _dataController.stream;

  @override
  Stream<void> get connectionClosed => _closedController.stream;

  void _connectTo(InMemoryTransportConnection peer) {
    _peer = peer;
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen || _peer == null || !_peer!._isOpen) {
      throw StateError('Connection is closed');
    }

    // Simulate async delivery
    scheduleMicrotask(() {
      if (_peer != null && _peer!._isOpen) {
        _peer!._dataController.add(data);
      }
    });
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;

    _closedController.add(null);
    await _dataController.close();
    await _closedController.close();

    // Close peer connection too
    if (_peer != null && _peer!._isOpen) {
      await _peer!.close();
    }
  }
}

/// A no-op handshake protocol for the in-memory example
/// This assumes we already know the peer ID from the connection context
class NoOpHandshakeProtocol implements HandshakeProtocol {
  const NoOpHandshakeProtocol(this.remotePeerId);

  final PeerId remotePeerId;

  @override
  Future<HandshakeResult> initiateHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  ) async {
    return HandshakeResult(success: true, remotePeerId: remotePeerId);
  }

  @override
  Future<HandshakeResult> respondToHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  ) async {
    return HandshakeResult(success: true, remotePeerId: remotePeerId);
  }
}

Future<void> main() async {
  print('🚀 Starting Transport Library Example');

  // Create two transport managers representing different peers
  final peer1Id = PeerId('peer-1');
  final peer2Id = PeerId('peer-2');

  final peer1Address = DeviceAddress('peer-1-addr');
  final peer2Address = DeviceAddress('peer-2-addr');

  // Configure peer 1
  final peer1Config = TransportConfig(
    localPeerId: peer1Id,
    protocol: InMemoryTransportProtocol(peer1Address),
    handshakeProtocol: NoOpHandshakeProtocol(
      peer2Id,
    ), // Expect to connect to peer2
    connectionPolicy: const AutoConnectPolicy(),
    peerStore: InMemoryPeerStore(),
  );

  // Configure peer 2
  final peer2Config = TransportConfig(
    localPeerId: peer2Id,
    protocol: InMemoryTransportProtocol(peer2Address),
    handshakeProtocol: NoOpHandshakeProtocol(
      peer1Id,
    ), // Expect connections from peer1
    connectionPolicy: const AutoConnectPolicy(),
    peerStore: InMemoryPeerStore(),
  );

  final peer1Transport = TransportManager(peer1Config);
  final peer2Transport = TransportManager(peer2Config);

  // Set up event listeners
  peer1Transport.peerUpdates.listen((peer) {
    print('👥 Peer 1 sees peer update: ${peer.id.value} -> ${peer.status}');
  });

  peer1Transport.messagesReceived.listen((message) {
    final text = String.fromCharCodes(message.data);
    print('📩 Peer 1 received: "$text" from ${message.senderId.value}');
  });

  peer1Transport.connectionRequests.listen((request) {
    print('🔗 Peer 1 received connection request from ${request.peerId.value}');
  });

  peer2Transport.peerUpdates.listen((peer) {
    print('👥 Peer 2 sees peer update: ${peer.id.value} -> ${peer.status}');
  });

  peer2Transport.messagesReceived.listen((message) {
    final text = String.fromCharCodes(message.data);
    print('📩 Peer 2 received: "$text" from ${message.senderId.value}');
  });

  peer2Transport.connectionRequests.listen((request) {
    print('🔗 Peer 2 received connection request from ${request.peerId.value}');
  });

  try {
    // Start both transport managers
    print('\n📡 Starting transport managers...');
    await peer1Transport.start();
    await peer2Transport.start();

    // Simulate device discovery and automatic connection
    print('\n🔍 Simulating device discovery...');

    // Simulate peer 1 discovering peer 2's device
    if (peer1Config.protocol is InMemoryTransportProtocol) {
      (peer1Config.protocol as InMemoryTransportProtocol)
          .simulateReceivedBroadcast(
            address: peer2Address,
            displayName: 'Peer 2 Device',
          );
    }

    // Give time for automatic connection to establish
    await Future.delayed(const Duration(milliseconds: 500));

    print('\n🤝 Checking if connection was established automatically...');
    final peer2 = peer1Transport.getPeer(peer2Id);
    if (peer2 != null && peer2.status == PeerStatus.connected) {
      print('✅ Connection successful (automatically established)!');

      // Send a message from peer 1 to peer 2
      print('\n💬 Sending message from peer 1 to peer 2...');
      final message1 = TransportMessage(
        senderId: peer1Id,
        recipientId: peer2Id,
        data: Uint8List.fromList('Hello from Peer 1! 👋'.codeUnits),
        timestamp: DateTime.now(),
      );

      final sent1 = await peer1Transport.sendMessage(message1);
      print('📤 Message sent: $sent1');

      // Wait a moment for delivery
      await Future.delayed(const Duration(milliseconds: 100));

      // Send a reply from peer 2 to peer 1
      print('\n💬 Sending reply from peer 2 to peer 1...');
      final message2 = TransportMessage(
        senderId: peer2Id,
        recipientId: peer1Id,
        data: Uint8List.fromList('Hello back from Peer 2! 🎉'.codeUnits),
        timestamp: DateTime.now(),
      );

      final sent2 = await peer2Transport.sendMessage(message2);
      print('📤 Reply sent: $sent2');

      // Wait for message delivery
      await Future.delayed(const Duration(milliseconds: 200));

      // Show current peer lists
      print('\n📋 Current peer states:');
      print('Peer 1 knows about:');
      for (final peer in peer1Transport.peers) {
        print('  - ${peer.id.value}: ${peer.status}');
      }
      print('Peer 2 knows about:');
      for (final peer in peer2Transport.peers) {
        print('  - ${peer.id.value}: ${peer.status}');
      }

      // Disconnect
      print('\n🔌 Disconnecting peers...');
      await peer1Transport.disconnectFromPeer(peer2Id);

      await Future.delayed(const Duration(milliseconds: 100));
      print('Disconnection complete');
    } else {
      print('❌ Connection was not established automatically');
    }
  } catch (e, stackTrace) {
    print('💥 Error occurred: $e');
    print('Stack trace: $stackTrace');
  } finally {
    // Clean up
    print('\n🧹 Cleaning up...');
    await peer1Transport.dispose();
    await peer2Transport.dispose();

    // Dispose stores
    if (peer1Config.peerStore is InMemoryPeerStore) {
      await (peer1Config.peerStore! as InMemoryPeerStore).dispose();
    }
    if (peer2Config.peerStore is InMemoryPeerStore) {
      await (peer2Config.peerStore! as InMemoryPeerStore).dispose();
    }
  }

  print('✨ Example completed!');
}
