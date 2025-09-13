import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:transport/transport.dart';

/// Nearby Connections implementation of TransportProtocol
///
/// This implementation uses Google's Nearby Connections API to provide
/// peer-to-peer communication over Wi-Fi, Bluetooth, and Bluetooth LE.
class NearbyTransportProtocol implements TransportProtocol {
  final String serviceId;
  final String userName;

  // Connection management - transport level devices
  final Map<DeviceAddress, TransportDevice> _connectedTransportDevices = {};
  final Map<DeviceAddress, String> _transportAddressToDisplayName = {};
  final Set<DeviceAddress> _pendingConnections = {};
  final Map<DeviceAddress, int> _connectionAttempts = {};

  // Message handling
  final StreamController<IncomingData> _incomingDataController =
      StreamController.broadcast();

  bool _initialized = false;

  // Connection settings
  static const int _maxConnectionAttempts = 3;
  static const Duration _connectionRetryDelay = Duration(seconds: 2);
  static const int _maxConcurrentConnections = 8;
  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _connectionThrottleDelay = Duration(milliseconds: 500);

  final Strategy _connectionStrategy;

  NearbyTransportProtocol({
    required this.serviceId,
    required this.userName,
    Strategy connectionStrategy = Strategy.P2P_CLUSTER,
  }) : _connectionStrategy = connectionStrategy;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('🚀 Initializing NearbyTransportProtocol for $userName');

      // Start advertising this device
      await _startAdvertising();
      debugPrint('📡 Started advertising successfully');

      // Start discovering other devices
      await _startDiscovery();
      debugPrint('🔍 Started discovery successfully');

      _initialized = true;
      debugPrint('✅ NearbyTransportProtocol initialized successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize NearbyTransportProtocol: $e');
      rethrow;
    }
  }

  Future<void> _startAdvertising() async {
    debugPrint('📡 Starting advertising with strategy: $_connectionStrategy');
    await Nearby().startAdvertising(
      userName,
      _connectionStrategy,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: serviceId,
    );
  }

  Future<void> _startDiscovery() async {
    debugPrint('🔍 Starting discovery with strategy: $_connectionStrategy');
    await Nearby().startDiscovery(
      userName,
      _connectionStrategy,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: _onEndpointLost,
      serviceId: serviceId,
    );
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    debugPrint('🤝 Connection initiated with $id: ${info.endpointName}');

    // Check connection limits before accepting
    if (_connectedTransportDevices.length >= _maxConcurrentConnections) {
      debugPrint('❌ Connection limit reached, rejecting connection from $id');
      try {
        Nearby().rejectConnection(id);
      } catch (e) {
        debugPrint('❌ Failed to reject connection with $id: $e');
      }
      return;
    }

    // Auto-accept all connections
    try {
      Nearby().acceptConnection(
        id,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: _onPayloadTransferUpdate,
      );
      debugPrint('✅ Auto-accepted connection with $id');
    } catch (e) {
      debugPrint('❌ Failed to accept connection with $id: $e');
    }
  }

  void _onConnectionResult(String id, Status status) {
    debugPrint('🔗 Connection result for $id: $status');
    final transportAddress = DeviceAddress(id);

    _pendingConnections.remove(transportAddress);

    if (status == Status.CONNECTED) {
      final displayName =
          _transportAddressToDisplayName[transportAddress] ?? 'Unknown';
      final transportPeer = TransportDevice(
        address: transportAddress,
        displayName: displayName,
        connectedAt: DateTime.now(),
        isActive: true,
      );
      _connectedTransportDevices[transportAddress] = transportPeer;
      _connectionAttempts.remove(transportAddress);
      debugPrint(
        '🎉 Successfully connected to transport peer $id ($displayName) (Total: ${_connectedTransportDevices.length})',
      );
    } else {
      _connectedTransportDevices.remove(DeviceAddress(id));
      debugPrint('❌ Connection failed with $id: $status');
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    final address = DeviceAddress(endpointId);
    final bytes = payload.bytes;
    if (payload.type == PayloadType.BYTES && bytes != null) {
      debugPrint('Received ${bytes.length} bytes from $address');

      final incomingData = IncomingData(
        fromAddress: address,
        data: payload.bytes!,
        timestamp: DateTime.now(),
      );

      _incomingDataController.add(incomingData);
    }
  }

  void _onPayloadTransferUpdate(
    String endpointId,
    PayloadTransferUpdate update,
  ) {
    if (update.status == PayloadStatus.SUCCESS) {
      debugPrint('✅ Payload transfer successful to $endpointId');
    } else if (update.status == PayloadStatus.FAILURE) {
      debugPrint('❌ Payload transfer failed to $endpointId');
    }
  }

  void _onDisconnected(String id) {
    debugPrint('💔 Disconnected from transport peer $id');

    final transportAddress = DeviceAddress(id);
    _connectedTransportDevices.remove(transportAddress);
    _transportAddressToDisplayName.remove(transportAddress);
    _pendingConnections.remove(transportAddress);
    _connectionAttempts.remove(transportAddress);

    debugPrint(
      '📊 Remaining transport peers: ${_connectedTransportDevices.length}',
    );
  }

  void _onEndpointFound(String id, String name, String serviceId) {
    final address = DeviceAddress(id);
    debugPrint(
      '🎯 FOUND DEVICE! Address: $address, Name: $name, Service: $serviceId',
    );

    // Store display name for later use
    _transportAddressToDisplayName[address] = name;

    // Check connection limits before attempting connection
    if (_connectedTransportDevices.length + _pendingConnections.length >=
        _maxConcurrentConnections) {
      debugPrint(
        '⚠️ Connection limit reached, skipping connection to $name ($address)',
      );
      return;
    }

    // Skip if we've already tried too many times
    if ((_connectionAttempts[address] ?? 0) >= _maxConnectionAttempts) {
      debugPrint('⚠️ Max attempts reached for $name ($address), skipping');
      return;
    }

    // Throttle connection attempts
    Future.delayed(_connectionThrottleDelay, () {
      if (!_connectedTransportDevices.containsKey(address) &&
          !_pendingConnections.contains(address)) {
        _requestConnection(address, name);
      }
    });
  }

  void _onEndpointLost(String? id) {
    if (id != null) {
      debugPrint('📤 Lost device: $id');
      final transportAddress = DeviceAddress(id);
      _connectedTransportDevices.remove(transportAddress);
      _transportAddressToDisplayName.remove(transportAddress);
    }
  }

  void _requestConnection(DeviceAddress address, String name) async {
    // Check if already connected or pending
    if (_connectedTransportDevices.containsKey(address) ||
        _pendingConnections.contains(address)) {
      debugPrint(
        '⚠️ Connection to $name ($address) already exists or is pending',
      );
      return;
    }

    // Check connection attempts
    final attempts = _connectionAttempts[address] ?? 0;
    if (attempts >= _maxConnectionAttempts) {
      debugPrint('❌ Max connection attempts reached for $name ($address)');
      return;
    }

    _pendingConnections.add(address);
    _connectionAttempts[address] = attempts + 1;

    debugPrint(
      '📞 Requesting connection to $name ($address) (attempt ${attempts + 1}/$_maxConnectionAttempts)',
    );

    try {
      await Nearby().requestConnection(
        userName,
        address.value,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      debugPrint('❌ Failed to request connection to $address: $e');
      _pendingConnections.remove(address);

      if (attempts + 1 < _maxConnectionAttempts) {
        Timer(_connectionRetryDelay, () {
          _requestConnection(address, name);
        });
      }
    }
  }

  @override
  Future<void> sendData(
    DeviceAddress address,
    Uint8List data, {
    Duration? timeout = _defaultTimeout,
  }) async {
    await Nearby().sendBytesPayload(address.value, data);
  }

  @override
  Stream<IncomingData> get incomingData => _incomingDataController.stream;

  @override
  Future<List<TransportDevice>> discoverDevices() async {
    if (!_initialized) {
      throw StateError('Transport not initialized');
    }

    return _connectedTransportDevices.values.toList();
  }

  @override
  Future<void> shutdown() async {
    if (!_initialized) return;

    try {
      debugPrint('🛑 Shutting down NearbyTransportProtocol...');

      // Stop Nearby Connections services
      await Nearby().stopAdvertising();
      debugPrint('⏹️ Stopped advertising');

      await Nearby().stopDiscovery();
      debugPrint('⏹️ Stopped discovery');

      await Nearby().stopAllEndpoints();
      debugPrint('⏹️ Stopped all endpoints');

      // Close streams
      await _incomingDataController.close();

      // Clear state
      _connectedTransportDevices.clear();
      _transportAddressToDisplayName.clear();
      _pendingConnections.clear();
      _connectionAttempts.clear();
      _initialized = false;

      debugPrint('✅ NearbyTransportProtocol shut down successfully');
    } catch (e) {
      debugPrint('❌ Error shutting down transport: $e');
    }
  }
}
