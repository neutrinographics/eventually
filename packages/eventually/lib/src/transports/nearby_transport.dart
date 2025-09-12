import 'dart:async';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import '../transport.dart';

// Stubs for nearby_connections package when not available
enum Strategy { P2P_CLUSTER, P2P_STAR, P2P_POINT_TO_POINT }

enum Status { CONNECTED, DISCONNECTED, ERROR }

class ConnectionInfo {
  final String endpointName;
  final String authenticationToken;
  final bool isIncomingConnection;

  ConnectionInfo({
    required this.endpointName,
    required this.authenticationToken,
    required this.isIncomingConnection,
  });
}

class Payload {
  final List<int>? bytes;
  final String? filePath;
  final int id;

  Payload({this.bytes, this.filePath, required this.id});
}

class PayloadTransferUpdate {
  final int payloadId;
  final Status status;
  final int totalBytes;
  final int bytesTransferred;

  PayloadTransferUpdate({
    required this.payloadId,
    required this.status,
    required this.totalBytes,
    required this.bytesTransferred,
  });
}

class _NearbyStub {
  Future<bool> askLocationAndExternalStoragePermission() async => true;

  Future<void> startAdvertising(
    String userNickName,
    Strategy strategy, {
    required Function(String, ConnectionInfo) onConnectionInitiated,
    required Function(String, Status) onConnectionResult,
    required Function(String) onDisconnected,
    String? serviceId,
  }) async {}

  Future<void> startDiscovery(
    String serviceId,
    Strategy strategy, {
    required Function(String, String, String) onEndpointFound,
    required Function(String) onEndpointLost,
  }) async {}

  Future<void> stopAdvertising() async {}
  Future<void> stopDiscovery() async {}
  Future<void> disconnectFromEndpoint(String endpointId) async {}
  Future<void> sendBytesPayload(String endpointId, List<int> bytes) async {}

  Future<void> acceptConnection(
    String endpointId, {
    required Function(String, Payload) onPayLoadRecieved,
    required Function(String, PayloadTransferUpdate) onPayloadTransferUpdate,
  }) async {}

  Future<void> requestConnection(
    String userNickName,
    String endpointId, {
    required Function(String, ConnectionInfo) onConnectionInitiated,
    required Function(String, Status) onConnectionResult,
    required Function(String) onDisconnected,
  }) async {}
}

_NearbyStub Nearby() => _NearbyStub();

/// Exception thrown when nearby transport operations fail.
class NearbyTransportException implements Exception {
  const NearbyTransportException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('NearbyTransportException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}

/// Transport implementation using Google Nearby Connections for peer-to-peer communication.
///
/// This transport is ideal for local device-to-device communication without requiring
/// internet connectivity. It uses Bluetooth and WiFi to discover and connect to nearby devices.
class NearbyTransport implements Transport {
  /// The local node identifier.
  final String nodeId;

  /// Display name shown to other devices during discovery.
  final String displayName;

  /// Service ID for this application (should be unique per app).
  final String serviceId;

  /// Connection strategy for nearby connections.
  final Strategy strategy;

  // Internal state
  bool _isInitialized = false;
  bool _isAdvertising = false;
  bool _isDiscovering = false;

  final Map<String, TransportPeer> _discoveredPeers = {};
  final Map<String, TransportPeer> _connectedPeers = {};
  final StreamController<IncomingBytes> _incomingBytesController =
      StreamController<IncomingBytes>.broadcast();

  /// Creates a nearby transport with the specified configuration.
  NearbyTransport({
    required this.nodeId,
    required this.displayName,
    required this.serviceId,
    this.strategy = Strategy.P2P_CLUSTER,
  });

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request necessary permissions
      final granted = await Nearby().askLocationAndExternalStoragePermission();
      if (!granted) {
        throw const NearbyTransportException(
          'Location and storage permissions are required for Nearby Connections',
        );
      }

      // Set up connection lifecycle callbacks
      await Nearby().startAdvertising(
        displayName,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );

      await Nearby().startDiscovery(
        serviceId,
        strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
      );

      _isAdvertising = true;
      _isDiscovering = true;
      _isInitialized = true;
    } catch (e) {
      throw NearbyTransportException(
        'Failed to initialize nearby transport',
        cause: e,
      );
    }
  }

  @override
  Future<void> shutdown() async {
    if (!_isInitialized) return;

    try {
      if (_isAdvertising) {
        await Nearby().stopAdvertising();
        _isAdvertising = false;
      }

      if (_isDiscovering) {
        await Nearby().stopDiscovery();
        _isDiscovering = false;
      }

      // Disconnect from all peers
      for (final peer in _connectedPeers.values) {
        await Nearby().disconnectFromEndpoint(peer.address.value);
      }

      _connectedPeers.clear();
      _discoveredPeers.clear();
      _isInitialized = false;

      await _incomingBytesController.close();
    } catch (e) {
      throw NearbyTransportException(
        'Failed to shutdown nearby transport',
        cause: e,
      );
    }
  }

  @override
  Future<List<TransportPeer>> discoverPeers({Duration? timeout}) async {
    if (!_isInitialized) {
      throw const NearbyTransportException('Transport not initialized');
    }

    // Restart discovery to get fresh results
    if (_isDiscovering) {
      await Nearby().stopDiscovery();
    }

    await Nearby().startDiscovery(
      serviceId,
      strategy,
      onEndpointFound: _onEndpointFound,
      onEndpointLost: _onEndpointLost,
    );

    _isDiscovering = true;

    // Wait for discovery timeout or use default
    final discoveryTimeout = timeout ?? const Duration(seconds: 10);
    await Future.delayed(discoveryTimeout);

    return _discoveredPeers.values.toList();
  }

  @override
  Future<void> sendBytes(
    TransportPeer peer,
    Uint8List bytes, {
    Duration? timeout,
  }) async {
    if (!_isInitialized) {
      throw const NearbyTransportException('Transport not initialized');
    }

    final connectedPeer = _connectedPeers[peer.address.value];
    if (connectedPeer == null) {
      throw NearbyTransportException('Not connected to peer: ${peer.address}');
    }

    try {
      await Nearby().sendBytesPayload(peer.address.value, bytes);
    } catch (e) {
      throw NearbyTransportException(
        'Failed to send bytes to peer: ${peer.address}',
        cause: e,
      );
    }
  }

  @override
  Stream<IncomingBytes> get incomingBytes => _incomingBytesController.stream;

  @override
  Future<bool> isPeerReachable(TransportPeer transportPeer) async {
    if (!_isInitialized) return false;

    // Check if we have an active connection to this peer
    final connectedPeer = _connectedPeers[transportPeer.address.value];
    return connectedPeer != null && connectedPeer.isActive;
  }

  // Private callback methods for Nearby Connections

  void _onEndpointFound(
    String endpointId,
    String endpointName,
    String serviceId,
  ) {
    final peer = TransportPeer(
      address: TransportPeerAddress(endpointId),
      displayName: endpointName,
      protocol: 'nearby_connections',
      metadata: {
        'service_id': serviceId,
        'endpoint_id': endpointId,
        'discovered_at': DateTime.now().toIso8601String(),
      },
    );

    _discoveredPeers[endpointId] = peer;
  }

  void _onEndpointLost(String endpointId) {
    _discoveredPeers.remove(endpointId);

    // Also remove from connected peers if it was connected
    final connectedPeer = _connectedPeers[endpointId];
    if (connectedPeer != null) {
      _connectedPeers[endpointId] = connectedPeer.copyWith(isActive: false);
    }
  }

  void _onConnectionInitiated(
    String endpointId,
    ConnectionInfo connectionInfo,
  ) {
    // Auto-accept all connection requests
    // In a production app, you might want to show a dialog or implement
    // some authentication logic here
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
      onPayloadTransferUpdate: _onPayloadTransferUpdate,
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      // Find the discovered peer and mark it as connected
      final discoveredPeer = _discoveredPeers[endpointId];
      if (discoveredPeer != null) {
        final connectedPeer = discoveredPeer.copyWith(
          isActive: true,
          connectedAt: DateTime.now(),
          metadata: {
            ...discoveredPeer.metadata,
            'connected_at': DateTime.now().toIso8601String(),
            'status': 'connected',
          },
        );
        _connectedPeers[endpointId] = connectedPeer;
      } else {
        // Create a new peer entry if we don't have discovery info
        _connectedPeers[endpointId] = TransportPeer(
          address: TransportPeerAddress(endpointId),
          displayName: 'Unknown Device',
          protocol: 'nearby_connections',
          metadata: {
            'connected_at': DateTime.now().toIso8601String(),
            'status': 'connected',
          },
        );
      }
    } else {
      // Connection failed or was rejected
      _connectedPeers.remove(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    final peer = _connectedPeers[endpointId];
    if (peer != null) {
      _connectedPeers[endpointId] = peer.copyWith(isActive: false);
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    final peer = _connectedPeers[endpointId];
    if (peer != null && payload.bytes != null) {
      final incomingBytes = IncomingBytes(
        peer,
        Uint8List.fromList(payload.bytes!),
        DateTime.now(),
      );
      _incomingBytesController.add(incomingBytes);
    }
  }

  void _onPayloadTransferUpdate(
    String endpointId,
    PayloadTransferUpdate update,
  ) {
    // Handle payload transfer updates if needed
    // This could be used for progress tracking on large file transfers
  }

  /// Manually connect to a discovered peer.
  ///
  /// This method can be used to initiate connections to specific peers
  /// instead of waiting for incoming connection requests.
  Future<void> connectToPeer(TransportPeer peer) async {
    if (!_isInitialized) {
      throw const NearbyTransportException('Transport not initialized');
    }

    try {
      await Nearby().requestConnection(
        displayName,
        peer.address.value,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      throw NearbyTransportException(
        'Failed to connect to peer: ${peer.address}',
        cause: e,
      );
    }
  }

  /// Gets all currently connected peers.
  List<TransportPeer> get connectedPeers =>
      _connectedPeers.values.where((peer) => peer.isActive).toList();

  /// Gets all discovered peers (connected and not connected).
  List<TransportPeer> get discoveredPeers => _discoveredPeers.values.toList();
}
