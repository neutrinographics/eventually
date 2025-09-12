import 'dart:typed_data';
import 'package:eventually/eventually.dart';
import 'package:transport/transport.dart';

/// Example demonstrating how to use the Eventually library with the Transport library
/// for Merkle DAG synchronization between peers.
Future<void> main() async {
  print('🚀 Starting Eventually + Transport Example');

  // Create two nodes with different peer IDs
  final node1PeerId = PeerId('node-1');
  final node2PeerId = PeerId('node-2');

  print('\n📦 Setting up Node 1');
  final node1 = await createNode(node1PeerId, 'Node 1 Device');

  print('📦 Setting up Node 2');
  final node2 = await createNode(node2PeerId, 'Node 2 Device');

  try {
    print('\n🔗 Starting transport managers');
    await node1.transport.start();
    await node2.transport.start();

    print('🔄 Initializing synchronizers');
    await node1.sync.initialize(node1.transport);
    await node2.sync.initialize(node2.transport);

    print('\n📊 Adding content to Node 1');
    // Add some content to node 1
    final block1 = Block.fromData(
      Uint8List.fromList('Hello, World!'.codeUnits),
      codec: MultiCodec.raw,
    );
    final block2 = Block.fromData(
      Uint8List.fromList('This is a test block'.codeUnits),
      codec: MultiCodec.raw,
    );

    await node1.sync.addBlock(block1);
    await node1.sync.addBlock(block2);

    print('✅ Added blocks to Node 1:');
    print('  - ${block1.cid}');
    print('  - ${block2.cid}');

    // Wait a bit for the announcements to propagate
    await Future.delayed(Duration(seconds: 1));

    print('\n🔍 Checking Node 2 content before sync');
    final hasBlock1Before = await node2.store.has(block1.cid);
    final hasBlock2Before = await node2.store.has(block2.cid);
    print('  - Node 2 has block1: $hasBlock1Before');
    print('  - Node 2 has block2: $hasBlock2Before');

    print('\n🔄 Simulating peer discovery and connection');
    // In a real scenario, this would happen automatically through transport discovery
    // For this example, we'll manually connect the peers

    // Create a mock connection between the nodes by simulating discovery
    final node1Address = DeviceAddress('node-1-address');
    final node2Address = DeviceAddress('node-2-address');

    // Simulate node 1 discovering node 2
    final node2Device = DiscoveredDevice(
      address: node2Address,
      displayName: 'Node 2 Device',
      discoveredAt: DateTime.now(),
    );

    // This would normally be handled by the transport's device discovery
    print('📡 Discovered devices and establishing connections...');

    // Wait for any automatic sync to occur
    await Future.delayed(Duration(seconds: 2));

    print('\n📊 Final state check');
    print('Node 1 stats: ${node1.sync.stats}');
    print('Node 2 stats: ${node2.sync.stats}');

    final node1Stats = await node1.store.getStats();
    final node2Stats = await node2.store.getStats();

    print(
      '\nNode 1 Store: ${node1Stats.totalBlocks} blocks, ${node1Stats.totalSize} bytes',
    );
    print(
      'Node 2 Store: ${node2Stats.totalBlocks} blocks, ${node2Stats.totalSize} bytes',
    );

    print('\n🎯 DAG Statistics');
    final node1DagStats = node1.dag.calculateStats();
    final node2DagStats = node2.dag.calculateStats();

    print('Node 1 DAG: $node1DagStats');
    print('Node 2 DAG: $node2DagStats');

    print('\n✨ Example completed successfully!');
  } catch (e, stackTrace) {
    print('❌ Error occurred: $e');
    print('Stack trace: $stackTrace');
  } finally {
    // Clean up
    print('\n🧹 Cleaning up...');
    await node1.dispose();
    await node2.dispose();
  }
}

/// Represents a complete node with storage, DAG, transport, and sync
class Node {
  Node({
    required this.store,
    required this.dag,
    required this.transport,
    required this.sync,
  });

  final Store store;
  final DAG dag;
  final TransportManager transport;
  final EventuallySynchronizer sync;

  Future<void> dispose() async {
    await sync.dispose();
    await transport.dispose();
    await store.close();
  }
}

/// Creates a complete node with all necessary components
Future<Node> createNode(PeerId peerId, String deviceName) async {
  // Create storage and DAG
  final store = MemoryStore();
  final dag = DAG();

  // Create transport configuration
  final transportConfig = TransportConfig(
    localPeerId: peerId,
    protocol: InMemoryTransportProtocol(DeviceAddress('${peerId.value}-addr')),
    deviceDiscovery: BroadcastDeviceDiscovery(
      localDisplayName: deviceName,
      broadcastInterval: Duration(seconds: 2),
    ),
    connectionPolicy: AutoConnectPolicy(),
    peerStore: InMemoryPeerStore(),
  );

  // Create transport manager
  final transport = TransportManager(transportConfig);

  // Create synchronizer
  final sync = EventuallySynchronizer(
    store: store,
    dag: dag,
    config: SyncConfig(announceNewBlocks: true, autoRequestMissing: true),
  );

  // Set up event listeners
  sync.syncEvents.listen((event) {
    switch (event) {
      case BlocksAnnounced event:
        print('📢 ${peerId.value}: Announced ${event.cids.length} blocks');
        break;
      case BlocksRequested event:
        print('📥 ${peerId.value}: Requested ${event.cids.length} blocks');
        break;
      case BlockReceived event:
        print(
          '✅ ${peerId.value}: Received block ${event.cid} from ${event.fromPeer.value}',
        );
        break;
      case SyncError event:
        print('❌ ${peerId.value}: Sync error - ${event.error}');
        break;
    }
  });

  transport.peerUpdates.listen((peer) {
    print('👥 ${peerId.value}: Peer ${peer.id.value} -> ${peer.status}');
  });

  return Node(store: store, dag: dag, transport: transport, sync: sync);
}

/// Simple in-memory transport protocol for demonstration
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
  Stream<IncomingConnectionAttempt> get incomingConnections =>
      _incomingController.stream;

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
  Future<TransportConnection?> connect(DeviceAddress targetAddress) async {
    final target = _instances[targetAddress.value];
    final listener = _listeners[targetAddress.value];

    if (target == null || listener == null) {
      return null;
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
    Future.microtask(() {
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

    if (_peer != null && _peer!._isOpen) {
      await _peer!.close();
    }
  }
}
