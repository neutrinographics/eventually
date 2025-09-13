import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:transport/transport.dart';

/// Nearby Connections implementation of TransportProtocol
///
/// This implementation uses Google's Nearby Connections API to provide
/// peer-to-peer communication over Wi-Fi, Bluetooth, and Bluetooth LE.
class NearbyTransportProtocol implements TransportProtocol {
  /// Service ID for the nearby connections service
  final String serviceId;

  /// Display name shown to other devices during discovery
  final String displayName;

  /// Connection strategy to use
  final Strategy strategy;

  // State management
  bool _isListening = false;
  bool _isDiscovering = false;

  // Connected endpoints tracking
  final Map<String, DeviceAddress> _connectedEndpoints = {};
  final Map<String, String> _endpointNames = {};

  // Stream controllers
  final StreamController<IncomingData> _incomingDataController =
      StreamController<IncomingData>.broadcast();
  final StreamController<ConnectionEvent> _connectionEventsController =
      StreamController<ConnectionEvent>.broadcast();
  final StreamController<DiscoveredDevice> _devicesDiscoveredController =
      StreamController<DiscoveredDevice>.broadcast();
  final StreamController<DeviceAddress> _devicesLostController =
      StreamController<DeviceAddress>.broadcast();

  /// Creates a new NearbyTransportProtocol instance
  NearbyTransportProtocol({
    required this.serviceId,
    required this.displayName,
    this.strategy = Strategy.P2P_CLUSTER,
  });

  @override
  Stream<ConnectionEvent> get connectionEvents =>
      _connectionEventsController.stream;

  @override
  Stream<DiscoveredDevice> get devicesDiscovered =>
      _devicesDiscoveredController.stream;

  @override
  Stream<DeviceAddress> get devicesLost => _devicesLostController.stream;

  @override
  Stream<IncomingData> get incomingData => _incomingDataController.stream;

  @override
  bool get isDiscovering => _isDiscovering;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> sendToAddress(DeviceAddress address, Uint8List data) async {
    try {
      // Find the endpoint ID for this address
      final endpointId = _findEndpointIdForAddress(address);
      if (endpointId == null) {
        debugPrint('❌ No endpoint found for address: ${address.value}');
        return false;
      }

      // Check if we're connected to this endpoint
      if (!_connectedEndpoints.containsKey(endpointId)) {
        debugPrint('❌ Not connected to endpoint: $endpointId');
        return false;
      }

      await Nearby().sendBytesPayload(endpointId, data);
      debugPrint('✅ Sent ${data.length} bytes to ${address.value}');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to send data to ${address.value}: $e');
      return false;
    }
  }

  @override
  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      debugPrint('⚠️ Discovery already running');
      return;
    }

    try {
      await Nearby().startDiscovery(
        displayName,
        strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: (String? endpointId) {
          if (endpointId != null) {
            _onEndpointLost(endpointId);
          }
        },
        serviceId: serviceId,
      );

      _isDiscovering = true;
      debugPrint('🔍 Started discovery with service ID: $serviceId');
    } catch (e) {
      debugPrint('❌ Failed to start discovery: $e');
      throw Exception('Failed to start discovery: $e');
    }
  }

  @override
  Future<void> startListening() async {
    if (_isListening) {
      debugPrint('⚠️ Already listening');
      return;
    }

    try {
      await Nearby().startAdvertising(
        displayName,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );

      _isListening = true;
      debugPrint('📡 Started advertising as: $displayName');
    } catch (e) {
      debugPrint('❌ Failed to start listening: $e');
      throw Exception('Failed to start listening: $e');
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) {
      debugPrint('⚠️ Discovery not running');
      return;
    }

    try {
      await Nearby().stopDiscovery();
      _isDiscovering = false;
      debugPrint('🛑 Stopped discovery');
    } catch (e) {
      debugPrint('❌ Failed to stop discovery: $e');
      throw Exception('Failed to stop discovery: $e');
    }
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening) {
      debugPrint('⚠️ Not listening');
      return;
    }

    try {
      await Nearby().stopAdvertising();

      // Disconnect from all connected endpoints
      for (final endpointId in _connectedEndpoints.keys.toList()) {
        await Nearby().disconnectFromEndpoint(endpointId);
      }

      _connectedEndpoints.clear();
      _endpointNames.clear();
      _isListening = false;
      debugPrint('🛑 Stopped listening and disconnected all endpoints');
    } catch (e) {
      debugPrint('❌ Failed to stop listening: $e');
      throw Exception('Failed to stop listening: $e');
    }
  }

  /// Dispose of resources and close streams
  Future<void> dispose() async {
    await stopListening();
    await stopDiscovery();

    if (!_incomingDataController.isClosed) {
      await _incomingDataController.close();
    }
    if (!_connectionEventsController.isClosed) {
      await _connectionEventsController.close();
    }
    if (!_devicesDiscoveredController.isClosed) {
      await _devicesDiscoveredController.close();
    }
    if (!_devicesLostController.isClosed) {
      await _devicesLostController.close();
    }

    debugPrint('🧹 NearbyTransportProtocol disposed');
  }

  // Private callback methods

  void _onEndpointFound(
    String endpointId,
    String endpointName,
    String serviceId,
  ) {
    debugPrint('👋 Found device: $endpointName ($endpointId)');

    _endpointNames[endpointId] = endpointName;

    final device = DiscoveredDevice(
      address: DeviceAddress(endpointId),
      displayName: endpointName,
      discoveredAt: DateTime.now(),
      metadata: {
        'service_id': serviceId,
        'endpoint_id': endpointId,
        'transport_type': 'nearby_connections',
      },
    );

    if (!_devicesDiscoveredController.isClosed) {
      _devicesDiscoveredController.add(device);
    }
  }

  void _onEndpointLost(String endpointId) {
    final endpointName = _endpointNames[endpointId] ?? 'Unknown';
    debugPrint('👋 Lost device: $endpointName ($endpointId)');

    _endpointNames.remove(endpointId);

    final address = DeviceAddress(endpointId);
    if (!_devicesLostController.isClosed) {
      _devicesLostController.add(address);
    }

    // If we were connected, mark as disconnected
    if (_connectedEndpoints.containsKey(endpointId)) {
      _connectedEndpoints.remove(endpointId);

      final event = ConnectionEvent(
        address: address,
        type: ConnectionEventType.disconnected,
        timestamp: DateTime.now(),
      );

      if (!_connectionEventsController.isClosed) {
        _connectionEventsController.add(event);
      }
    }
  }

  void _onConnectionInitiated(
    String endpointId,
    ConnectionInfo connectionInfo,
  ) {
    final endpointName =
        _endpointNames[endpointId] ?? connectionInfo.endpointName;
    debugPrint('🤝 Connection initiated with: $endpointName ($endpointId)');

    // Store the endpoint name
    _endpointNames[endpointId] = endpointName;

    // Auto-accept all connections
    // In a production app, you might want to show a dialog or use a policy
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: _onPayloadTransferUpdate,
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    final endpointName = _endpointNames[endpointId] ?? 'Unknown';
    final address = DeviceAddress(endpointId);

    if (status == Status.CONNECTED) {
      debugPrint('✅ Connected to: $endpointName ($endpointId)');

      _connectedEndpoints[endpointId] = address;

      final event = ConnectionEvent(
        address: address,
        type: ConnectionEventType.connected,
        timestamp: DateTime.now(),
      );

      if (!_connectionEventsController.isClosed) {
        _connectionEventsController.add(event);
      }
    } else {
      debugPrint(
        '❌ Failed to connect to: $endpointName ($endpointId) - $status',
      );

      _connectedEndpoints.remove(endpointId);

      final event = ConnectionEvent(
        address: address,
        type: ConnectionEventType.disconnected,
        timestamp: DateTime.now(),
      );

      if (!_connectionEventsController.isClosed) {
        _connectionEventsController.add(event);
      }
    }
  }

  void _onDisconnected(String endpointId) {
    final endpointName = _endpointNames[endpointId] ?? 'Unknown';
    debugPrint('👋 Disconnected from: $endpointName ($endpointId)');

    final address = DeviceAddress(endpointId);
    _connectedEndpoints.remove(endpointId);

    final event = ConnectionEvent(
      address: address,
      type: ConnectionEventType.disconnected,
      timestamp: DateTime.now(),
    );

    if (!_connectionEventsController.isClosed) {
      _connectionEventsController.add(event);
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.bytes != null) {
      final address = DeviceAddress(endpointId);

      final incomingData = IncomingData(
        data: payload.bytes!,
        fromAddress: address,
        timestamp: DateTime.now(),
      );

      debugPrint(
        '📨 Received ${payload.bytes!.length} bytes from: $endpointId',
      );

      if (!_incomingDataController.isClosed) {
        _incomingDataController.add(incomingData);
      }
    }
  }

  void _onPayloadTransferUpdate(
    String endpointId,
    PayloadTransferUpdate update,
  ) {
    // Handle payload transfer updates if needed
    // This could be used for progress tracking on large transfers
    if (update.status == PayloadStatus.SUCCESS) {
      debugPrint('✅ Payload transfer completed to/from: $endpointId');
    } else if (update.status == PayloadStatus.FAILURE) {
      debugPrint('❌ Payload transfer failed to/from: $endpointId');
    }
  }

  // Helper methods

  /// Find the endpoint ID for a given device address
  String? _findEndpointIdForAddress(DeviceAddress address) {
    // In our implementation, the device address value is the endpoint ID
    return address.value;
  }

  /// Request connection to a discovered device
  /// This is useful for initiating connections manually
  Future<void> requestConnection(DeviceAddress address) async {
    final endpointId = address.value;

    if (_connectedEndpoints.containsKey(endpointId)) {
      debugPrint('⚠️ Already connected to: $endpointId');
      return;
    }

    try {
      await Nearby().requestConnection(
        displayName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      debugPrint('📞 Requested connection to: $endpointId');
    } catch (e) {
      debugPrint('❌ Failed to request connection to $endpointId: $e');
      throw Exception('Failed to request connection: $e');
    }
  }

  /// Get list of currently connected device addresses
  List<DeviceAddress> get connectedDevices =>
      _connectedEndpoints.values.toList();

  /// Check if connected to a specific device
  bool isConnectedTo(DeviceAddress address) {
    return _connectedEndpoints.containsKey(address.value);
  }
}
