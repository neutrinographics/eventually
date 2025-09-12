import 'dart:async';
import 'dart:typed_data';
import 'dart:math';

import 'package:transport/transport.dart';

/// A simple in-memory transport protocol for demonstration purposes
class InMemoryTransportProtocol implements TransportProtocol {
  InMemoryTransportProtocol(this.address) {
    _incomingController =
        StreamController<IncomingConnectionAttempt>.broadcast();
  }

  static final Map<String, InMemoryTransportProtocol> _instances = {};
  static final Map<String, StreamController<IncomingConnectionAttempt>>
  _listeners = {};

  final DeviceAddress address;
  bool _isListening = false;
  late final StreamController<IncomingConnectionAttempt> _incomingController;

  @override
  bool get isListening => _isListening;

  @override
  Stream<IncomingConnectionAttempt> get incomingConnections {
    return _incomingController.stream;
  }

  @override
  Future<void> startListening(DeviceAddress address) async {
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
    approvalHandler: const AutoApprovalHandler(),
    peerStore: InMemoryPeerStore(),
  );

  // Configure peer 2
  final peer2Config = TransportConfig(
    localPeerId: peer2Id,
    protocol: InMemoryTransportProtocol(peer2Address),
    handshakeProtocol: NoOpHandshakeProtocol(
      peer1Id,
    ), // Expect connections from peer1
    approvalHandler: const AutoApprovalHandler(),
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
    await peer1Transport.start(listenAddress: peer1Address);
    await peer2Transport.start(listenAddress: peer2Address);

    // Manually add peer 2 to peer 1's peer list (simulating discovery)
    print('\n🔍 Simulating peer discovery...');
    final discoveredPeer2 = Peer(
      id: peer2Id,
      address: peer2Address,
      status: PeerStatus.discovered,
      lastSeen: DateTime.now(),
    );

    // Add peer to store (this would normally be done by discovery)
    await peer1Config.peerStore!.storePeer(discoveredPeer2);

    // Also add peer 1 to peer 2's store for bidirectional messaging
    final discoveredPeer1 = Peer(
      id: peer1Id,
      address: peer1Address,
      status: PeerStatus.discovered,
      lastSeen: DateTime.now(),
    );
    await peer2Config.peerStore!.storePeer(discoveredPeer1);

    // Wait a moment for the store update to propagate
    await Future.delayed(const Duration(milliseconds: 100));

    // Try to connect from peer 1 to peer 2
    print('\n🤝 Peer 1 attempting to connect to peer 2...');
    final connectionResult = await peer1Transport.connectToPeer(peer2Id);

    if (connectionResult.result == ConnectionResult.success) {
      print('✅ Connection successful!');

      // Send a message from peer 1 to peer 2
      print('\n💬 Sending message from peer 1 to peer 2...');
      final message1 = TransportMessage(
        senderId: peer1Id,
        recipientId: peer2Id,
        data: Uint8List.fromList('Hello from Peer 1! 👋'.codeUnits),
        timestamp: DateTime.now(),
        messageId: 'msg-${Random().nextInt(1000)}',
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
        messageId: 'msg-${Random().nextInt(1000)}',
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
      print('❌ Connection failed: ${connectionResult.error}');
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
