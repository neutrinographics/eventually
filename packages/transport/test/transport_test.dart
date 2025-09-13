import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:transport/transport.dart';

// Mock transport protocol for testing
class MockTransportProtocol implements TransportProtocol {
  MockTransportProtocol();

  final StreamController<IncomingData> _incomingDataController =
      StreamController<IncomingData>.broadcast();

  bool _initialized = false;
  final List<TransportDevice> _mockDevices = [];

  @override
  Stream<IncomingData> get incomingData => _incomingDataController.stream;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> shutdown() async {
    _initialized = false;
  }

  @override
  Future<void> sendData(
    DeviceAddress address,
    Uint8List data, {
    Duration? timeout,
  }) async {
    // Simulate successful sending
  }

  @override
  Future<List<TransportDevice>> discoverDevices() async {
    return _mockDevices.toList();
  }

  void simulateIncomingData(DeviceAddress fromAddress, Uint8List data) {
    final incomingData = IncomingData(
      data: data,
      fromAddress: fromAddress,
      timestamp: DateTime.now(),
    );
    _incomingDataController.add(incomingData);
  }

  void addMockDevice(TransportDevice device) {
    _mockDevices.add(device);
  }

  void removeMockDevice(DeviceAddress address) {
    _mockDevices.removeWhere((device) => device.address == address);
  }

  Future<void> dispose() async {
    await _incomingDataController.close();
  }

  // Helper method to create handshake response data
  Uint8List createHandshakeResponse(Uint8List data, String handshakeId) {
    final idBytes = Uint8List.fromList(handshakeId.codeUnits);
    final result = Uint8List(3 + 1 + idBytes.length + 1 + data.length);
    result[0] = 0x48; // 'H'
    result[1] = 0x53; // 'S'
    result[2] = 0x4B; // 'K'
    result[3] = 0x01; // Response flag
    result.setRange(4, 4 + idBytes.length, idBytes);
    result[4 + idBytes.length] = 0x00; // Null terminator
    result.setRange(4 + idBytes.length + 1, result.length, data);
    return result;
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

      await transport.stop();
      expect(transport.isStarted, isFalse);
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

    test('emits peer updates from loaded peers', () async {
      // Store a peer before starting
      final storedPeer = Peer(
        id: PeerId('stored-peer'),
        address: DeviceAddress('stored-addr'),
        status: PeerStatus.discovered,
      );
      await peerStore.storePeer(storedPeer);

      final peerCompleter = Completer<Peer>();
      transport.peerUpdates.listen(peerCompleter.complete);

      // Start the transport - this should load and emit stored peers
      await transport.start();

      final emittedPeer = await peerCompleter.future;
      expect(emittedPeer, equals(storedPeer));
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

    test('discovers mock devices', () async {
      final mockDevice = TransportDevice(
        address: DeviceAddress('test-device'),
        displayName: 'Test Device',
        connectedAt: DateTime.now(),
        isActive: true,
      );

      mockProtocol.addMockDevice(mockDevice);
      await transport.start();

      // Wait a moment for discovery to run
      await Future.delayed(Duration(milliseconds: 100));

      // The transport should have discovered our mock device
      // (actual peer creation would depend on successful handshake)
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

  group('Transport Config', () {
    test('creates valid configuration', () {
      final config = TransportConfig(
        localPeerId: PeerId('test-peer'),
        protocol: MockTransportProtocol(),
      );

      expect(config.localPeerId.value, equals('test-peer'));
      expect(config.handshakeTimeout, equals(const Duration(seconds: 10)));
      expect(config.discoveryInterval, equals(const Duration(seconds: 30)));
    });

    test('uses custom timeout values', () {
      final config = TransportConfig(
        localPeerId: PeerId('test-peer'),
        protocol: MockTransportProtocol(),
        handshakeTimeout: const Duration(seconds: 5),
        discoveryInterval: const Duration(seconds: 15),
      );

      expect(config.handshakeTimeout, equals(const Duration(seconds: 5)));
      expect(config.discoveryInterval, equals(const Duration(seconds: 15)));
    });
  });
}
