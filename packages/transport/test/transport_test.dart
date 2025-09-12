import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:transport/transport.dart';

// Mock transport protocol for testing
class MockTransportProtocol implements TransportProtocol {
  MockTransportProtocol();

  final StreamController<IncomingConnectionAttempt> _incomingController =
      StreamController<IncomingConnectionAttempt>.broadcast();

  final Map<String, MockTransportConnection> _connections = {};
  bool _isListening = false;

  @override
  bool get isListening => _isListening;

  @override
  Stream<IncomingConnectionAttempt> get incomingConnections =>
      _incomingController.stream;

  @override
  Future<void> startListening() async {
    _isListening = true;
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
  }

  @override
  Future<TransportConnection?> connect(DeviceAddress address) async {
    final connection = MockTransportConnection(address);
    _connections[address.value] = connection;
    return connection;
  }

  void simulateIncomingConnection(DeviceAddress fromAddress) {
    final connection = MockTransportConnection(fromAddress);
    final attempt = IncomingConnectionAttempt(
      connection: connection,
      address: fromAddress,
    );
    _incomingController.add(attempt);
  }

  Future<void> dispose() async {
    await _incomingController.close();
    for (final connection in _connections.values) {
      await connection.close();
    }
    _connections.clear();
  }
}

class MockTransportConnection implements TransportConnection {
  MockTransportConnection(this.remoteAddress);

  @override
  final DeviceAddress remoteAddress;

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  final StreamController<void> _closedController =
      StreamController<void>.broadcast();

  bool _isOpen = true;

  @override
  bool get isOpen => _isOpen;

  @override
  Stream<Uint8List> get dataReceived => _dataController.stream;

  @override
  Stream<void> get connectionClosed => _closedController.stream;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen) throw StateError('Connection is closed');
    // For testing, we can simulate receiving our own data
    scheduleMicrotask(() => _dataController.add(data));
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    _closedController.add(null);
    await _dataController.close();
    await _closedController.close();
  }

  // Test helper methods
  void simulateReceivedData(Uint8List data) {
    if (_isOpen) {
      _dataController.add(data);
    }
  }

  void simulateConnectionClosed() {
    if (_isOpen) {
      _isOpen = false;
      _closedController.add(null);
    }
  }
}

void main() {
  group('Models', () {
    test('PeerId equality works correctly', () {
      final peer1 = PeerId('test-peer');
      final peer2 = PeerId('test-peer');
      final peer3 = PeerId('other-peer');

      expect(peer1, equals(peer2));
      expect(peer1.hashCode, equals(peer2.hashCode));
      expect(peer1, isNot(equals(peer3)));
    });

    test('DeviceAddress equality works correctly', () {
      final addr1 = DeviceAddress('192.168.1.1:8080');
      final addr2 = DeviceAddress('192.168.1.1:8080');
      final addr3 = DeviceAddress('192.168.1.2:8080');

      expect(addr1, equals(addr2));
      expect(addr1.hashCode, equals(addr2.hashCode));
      expect(addr1, isNot(equals(addr3)));
    });

    test('Peer copyWith works correctly', () {
      final peer = Peer(
        id: PeerId('test'),
        address: DeviceAddress('addr'),
        status: PeerStatus.discovered,
      );

      final updatedPeer = peer.copyWith(status: PeerStatus.connected);

      expect(updatedPeer.id, equals(peer.id));
      expect(updatedPeer.address, equals(peer.address));
      expect(updatedPeer.status, equals(PeerStatus.connected));
    });

    test('TransportMessage creation works correctly', () {
      final message = TransportMessage(
        senderId: PeerId('sender'),
        recipientId: PeerId('recipient'),
        data: Uint8List.fromList([1, 2, 3, 4]),
        timestamp: DateTime.now(),
      );

      expect(message.senderId.value, equals('sender'));
      expect(message.recipientId.value, equals('recipient'));
      expect(message.data, equals(Uint8List.fromList([1, 2, 3, 4])));
    });
  });

  group('Default Implementations', () {
    group('InMemoryPeerStore', () {
      late InMemoryPeerStore store;

      setUp(() {
        store = InMemoryPeerStore();
      });

      tearDown(() async {
        await store.dispose();
      });

      test('can store and retrieve peers', () async {
        final peer = Peer(
          id: PeerId('test-peer'),
          address: DeviceAddress('test-addr'),
          status: PeerStatus.discovered,
        );

        await store.storePeer(peer);
        final retrieved = await store.getPeer(PeerId('test-peer'));

        expect(retrieved, equals(peer));
      });

      test('emits PeerAdded event when storing new peer', () async {
        final peer = Peer(
          id: PeerId('test-peer'),
          address: DeviceAddress('test-addr'),
          status: PeerStatus.discovered,
        );

        final eventCompleter = Completer<PeerStoreEvent>();
        store.peerUpdates.listen(eventCompleter.complete);

        await store.storePeer(peer);
        final event = await eventCompleter.future;

        expect(event, isA<PeerAdded>());
        expect(event.peer, equals(peer));
      });

      test('emits PeerUpdated event when updating existing peer', () async {
        final peer1 = Peer(
          id: PeerId('test-peer'),
          address: DeviceAddress('test-addr'),
          status: PeerStatus.discovered,
        );
        final peer2 = peer1.copyWith(status: PeerStatus.connected);

        // First store the initial peer
        await store.storePeer(peer1);

        // Set up listener for the next event (should be PeerUpdated)
        final events = <PeerStoreEvent>[];
        final subscription = store.peerUpdates.listen(events.add);

        // Clear any existing events
        await Future.delayed(Duration.zero);
        events.clear();

        // Store the updated peer
        await store.storePeer(peer2);

        // Wait for the event
        await Future.delayed(Duration(milliseconds: 10));

        await subscription.cancel();

        expect(events, hasLength(1));
        expect(events.first, isA<PeerUpdated>());
        expect(events.first.peer, equals(peer2));
      });

      test('can remove peers', () async {
        final peer = Peer(
          id: PeerId('test-peer'),
          address: DeviceAddress('test-addr'),
          status: PeerStatus.discovered,
        );

        await store.storePeer(peer);
        await store.removePeer(PeerId('test-peer'));

        final retrieved = await store.getPeer(PeerId('test-peer'));
        expect(retrieved, isNull);
      });

      test('returns all stored peers', () async {
        final peer1 = Peer(
          id: PeerId('peer-1'),
          address: DeviceAddress('addr-1'),
          status: PeerStatus.discovered,
        );
        final peer2 = Peer(
          id: PeerId('peer-2'),
          address: DeviceAddress('addr-2'),
          status: PeerStatus.connected,
        );

        await store.storePeer(peer1);
        await store.storePeer(peer2);

        final allPeers = await store.getAllPeers();
        expect(allPeers, hasLength(2));
        expect(allPeers, containsAll([peer1, peer2]));
      });
    });

    group('BroadcastDeviceDiscovery', () {
      late BroadcastDeviceDiscovery discovery;

      setUp(() {
        discovery = BroadcastDeviceDiscovery(
          localDisplayName: 'Local Device',
          broadcastInterval: const Duration(milliseconds: 100),
          deviceTimeout: const Duration(seconds: 1),
        );
      });

      tearDown(() async {
        await discovery.dispose();
      });

      test('starts and stops discovery correctly', () async {
        expect(discovery.isDiscovering, isFalse);

        await discovery.startDiscovery();
        expect(discovery.isDiscovering, isTrue);

        await discovery.stopDiscovery();
        expect(discovery.isDiscovering, isFalse);
      });

      test('emits discovered devices', () async {
        await discovery.startDiscovery();

        final deviceCompleter = Completer<DiscoveredDevice>();
        discovery.devicesDiscovered.listen(deviceCompleter.complete);

        discovery.simulateReceivedBroadcast(
          address: DeviceAddress('remote-addr'),
          displayName: 'Remote Device',
        );

        final discoveredDevice = await deviceCompleter.future;
        expect(discoveredDevice.address.value, equals('remote-addr'));
        expect(discoveredDevice.displayName, equals('Remote Device'));
      });

      test(
        'emits device updates when same device is discovered again',
        () async {
          await discovery.startDiscovery();

          final devices = <DiscoveredDevice>[];
          discovery.devicesDiscovered.listen(devices.add);

          discovery.simulateReceivedBroadcast(
            address: DeviceAddress('remote-addr'),
            displayName: 'Remote Device',
          );

          // Simulate same device discovered again with different metadata
          await Future.delayed(const Duration(milliseconds: 10));
          discovery.simulateReceivedBroadcast(
            address: DeviceAddress('remote-addr'),
            displayName: 'Remote Device Updated',
            metadata: {'version': '2.0'},
          );

          await Future.delayed(const Duration(milliseconds: 10));
          expect(devices, hasLength(2));
          expect(devices.last.displayName, equals('Remote Device Updated'));
        },
      );
    });

    group('Connection Approval Handlers', () {
      test('AutoApprovalHandler always accepts', () async {
        const handler = AutoApprovalHandler();
        final request = ConnectionRequest(
          peerId: PeerId('test-peer'),
          address: DeviceAddress('test-addr'),
          timestamp: DateTime.now(),
        );

        final response = await handler.handleConnectionRequest(request);
        expect(response, equals(ConnectionRequestResponse.accept));
      });

      test('RejectAllHandler always rejects', () async {
        const handler = RejectAllHandler();
        final request = ConnectionRequest(
          peerId: PeerId('test-peer'),
          address: DeviceAddress('test-addr'),
          timestamp: DateTime.now(),
        );

        final response = await handler.handleConnectionRequest(request);
        expect(response, equals(ConnectionRequestResponse.reject));
      });

      test('ManualApprovalHandler uses callback', () async {
        final handler = ManualApprovalHandler(
          (request) async => ConnectionRequestResponse.accept,
        );
        final request = ConnectionRequest(
          peerId: PeerId('test-peer'),
          address: DeviceAddress('test-addr'),
          timestamp: DateTime.now(),
        );

        final response = await handler.handleConnectionRequest(request);
        expect(response, equals(ConnectionRequestResponse.accept));
      });
    });
  });

  group('TransportManager', () {
    late MockTransportProtocol mockProtocol;
    late TransportManager transport;
    late InMemoryPeerStore peerStore;

    setUp(() {
      mockProtocol = MockTransportProtocol();
      peerStore = InMemoryPeerStore();

      final config = TransportConfig(
        localPeerId: PeerId('test-peer'),
        protocol: mockProtocol,
        handshakeProtocol: const JsonHandshakeProtocol(),
        approvalHandler: const AutoApprovalHandler(),
        deviceDiscovery: const NoOpDeviceDiscovery(),
        connectionPolicy: const ManualConnectPolicy(),
        peerStore: peerStore,
      );

      transport = TransportManager(config);
    });

    tearDown(() async {
      await transport.dispose();
      await peerStore.dispose();
      await mockProtocol.dispose();
    });

    test('starts and stops correctly', () async {
      expect(transport.isStarted, isFalse);

      await transport.start();
      expect(transport.isStarted, isTrue);
      expect(mockProtocol.isListening, isTrue);

      await transport.stop();
      expect(transport.isStarted, isFalse);
      expect(mockProtocol.isListening, isFalse);
    });

    test('loads peers from store on start', () async {
      final storedPeer = Peer(
        id: PeerId('stored-peer'),
        address: DeviceAddress('stored-addr'),
        status: PeerStatus.discovered,
      );

      await peerStore.storePeer(storedPeer);
      await transport.start();

      final peers = transport.peers;
      expect(peers, hasLength(1));
      expect(peers.first, equals(storedPeer));
    });

    test('emits peer updates from store', () async {
      await transport.start();

      final peerCompleter = Completer<Peer>();
      transport.peerUpdates.listen(peerCompleter.complete);

      final peer = Peer(
        id: PeerId('new-peer'),
        address: DeviceAddress('new-addr'),
        status: PeerStatus.connected,
      );

      await peerStore.storePeer(peer);
      final updatedPeer = await peerCompleter.future;

      expect(updatedPeer, equals(peer));
    });

    test('returns correct local peer ID', () {
      expect(transport.localPeerId.value, equals('test-peer'));
    });

    test('getPeer returns correct peer', () async {
      final peer = Peer(
        id: PeerId('test-peer-id'),
        address: DeviceAddress('test-addr'),
        status: PeerStatus.discovered,
      );

      await peerStore.storePeer(peer);
      await transport.start();

      final retrievedPeer = transport.getPeer(PeerId('test-peer-id'));
      expect(retrievedPeer, equals(peer));
    });

    test('returns null for unknown peer', () async {
      await transport.start();
      final peer = transport.getPeer(PeerId('unknown-peer'));
      expect(peer, isNull);
    });

    test('connectToPeer fails when not started', () async {
      final result = await transport.connectToPeer(PeerId('some-peer'));
      expect(result.result, equals(ConnectionResult.failed));
      expect(result.error, equals('Transport manager not started'));
    });

    test('connectToPeer fails for unknown peer', () async {
      await transport.start();
      final result = await transport.connectToPeer(PeerId('unknown-peer'));
      expect(result.result, equals(ConnectionResult.failed));
      expect(result.error, equals('Peer not found'));
    });

    test('sendMessage fails when not started', () async {
      final message = TransportMessage(
        senderId: PeerId('sender'),
        recipientId: PeerId('recipient'),
        data: Uint8List(0),
        timestamp: DateTime.now(),
      );

      final result = await transport.sendMessage(message);
      expect(result, isFalse);
    });

    test('sendMessage fails for disconnected peer', () async {
      await transport.start();

      final message = TransportMessage(
        senderId: PeerId('sender'),
        recipientId: PeerId('unknown-peer'),
        data: Uint8List(0),
        timestamp: DateTime.now(),
      );

      final result = await transport.sendMessage(message);
      expect(result, isFalse);
    });
  });

  group('Connection Policy', () {
    test('AutoConnectPolicy always returns true', () async {
      const policy = AutoConnectPolicy();
      final device = DiscoveredDevice(
        address: DeviceAddress('test-addr'),
        displayName: 'Test Device',
        discoveredAt: DateTime.now(),
      );

      final result = await policy.shouldConnectToDevice(device);
      expect(result, isTrue);
    });

    test('ManualConnectPolicy always returns false', () async {
      const policy = ManualConnectPolicy();
      final device = DiscoveredDevice(
        address: DeviceAddress('test-addr'),
        displayName: 'Test Device',
        discoveredAt: DateTime.now(),
      );

      final result = await policy.shouldConnectToDevice(device);
      expect(result, isFalse);
    });

    test('PolicyBasedConnectionPolicy uses callback', () async {
      final policy = PolicyBasedConnectionPolicy(
        (device) async => device.displayName.contains('Connect'),
      );

      final deviceToConnect = DiscoveredDevice(
        address: DeviceAddress('test-addr-1'),
        displayName: 'ConnectMe Device',
        discoveredAt: DateTime.now(),
      );

      final deviceToIgnore = DiscoveredDevice(
        address: DeviceAddress('test-addr-2'),
        displayName: 'Ignore Device',
        discoveredAt: DateTime.now(),
      );

      expect(await policy.shouldConnectToDevice(deviceToConnect), isTrue);
      expect(await policy.shouldConnectToDevice(deviceToIgnore), isFalse);
    });
  });

  group('Transport Config', () {
    test('creates valid configuration', () {
      final config = TransportConfig(
        localPeerId: PeerId('test-peer'),
        protocol: MockTransportProtocol(),
        handshakeProtocol: const JsonHandshakeProtocol(),
        approvalHandler: const AutoApprovalHandler(),
        deviceDiscovery: const NoOpDeviceDiscovery(),
        connectionPolicy: const ManualConnectPolicy(),
      );

      expect(config.localPeerId.value, equals('test-peer'));
      expect(config.connectionTimeout, equals(const Duration(seconds: 30)));
      expect(config.handshakeTimeout, equals(const Duration(seconds: 10)));
      expect(config.maxConnections, equals(100));
    });

    test('accepts custom timeouts and limits', () {
      final config = TransportConfig(
        localPeerId: PeerId('test-peer'),
        protocol: MockTransportProtocol(),
        handshakeProtocol: const JsonHandshakeProtocol(),
        approvalHandler: const AutoApprovalHandler(),
        connectionTimeout: const Duration(seconds: 60),
        handshakeTimeout: const Duration(seconds: 5),
        maxConnections: 50,
      );

      expect(config.connectionTimeout, equals(const Duration(seconds: 60)));
      expect(config.handshakeTimeout, equals(const Duration(seconds: 5)));
      expect(config.maxConnections, equals(50));
    });
  });
}
