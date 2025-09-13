import 'dart:async';
import 'dart:typed_data';

import 'models.dart';
import 'default_implementations.dart';

/// Abstract interface for low-level transport protocols (e.g., TCP, WebSocket, Bluetooth)
/// Includes connection management, device discovery, and direct data transmission
abstract interface class TransportProtocol {
  /// Start advertising local peer on the network.
  Future<void> startAdvertising();

  /// Stop advertising local peer on the network.
  Future<void> stopAdvertising();

  /// Start discovering devices on the network
  Future<void> startDiscovery();

  /// Stop discovering devices on the network
  Future<void> stopDiscovery();

  /// Send data directly to a device address
  /// Returns true if the data was sent successfully, false otherwise
  Future<bool> sendToAddress(DeviceAddress address, Uint8List data);

  /// Stream of incoming data with sender address information
  Stream<IncomingData> get incomingData;

  /// Stream of connection events (connected/disconnected from addresses)
  Stream<ConnectionEvent> get connectionEvents;

  /// Stream of newly discovered devices
  Stream<DiscoveredDevice> get devicesDiscovered;

  /// Stream of devices that are no longer available
  Stream<DeviceAddress> get devicesLost;

  /// Whether this transport is currently listening for connections
  bool get isListening;

  /// Whether discovery is currently active
  bool get isDiscovering;
}

/// Represents incoming data from a remote peer
class IncomingData {
  const IncomingData({
    required this.data,
    required this.fromAddress,
    required this.timestamp,
  });

  /// The raw data received
  final Uint8List data;

  /// The address the data came from
  final DeviceAddress fromAddress;

  /// When the data was received
  final DateTime timestamp;
}

/// Represents a connection event (connect/disconnect)
class ConnectionEvent {
  const ConnectionEvent({
    required this.address,
    required this.type,
    required this.timestamp,
  });

  /// The address involved in the connection event
  final DeviceAddress address;

  /// The type of connection event
  final ConnectionEventType type;

  /// When the event occurred
  final DateTime timestamp;
}

/// Types of connection events
enum ConnectionEventType {
  /// A connection to this address was established
  connected,

  /// A connection to this address was lost
  disconnected,
}

/// Abstract interface for handling the handshake process between peers
abstract interface class HandshakeProtocol {
  /// Perform a handshake as the initiator of the connection
  /// Returns handshake data to send to the remote peer
  Future<Uint8List> initiateHandshake(PeerId localPeerId);

  /// Handle incoming handshake data and return response data
  Future<HandshakeResult> handleIncomingHandshake(
    Uint8List handshakeData,
    DeviceAddress fromAddress,
    PeerId localPeerId,
  );

  /// Process handshake response data
  Future<HandshakeResult> processHandshakeResponse(
    Uint8List responseData,
    DeviceAddress fromAddress,
    PeerId localPeerId,
  );
}

/// Result of a handshake operation
class HandshakeResult {
  const HandshakeResult({
    required this.success,
    required this.remotePeerId,
    this.error,
    this.metadata = const {},
  });

  /// Whether the handshake was successful
  final bool success;

  /// The peer ID of the remote peer (if handshake was successful)
  final PeerId? remotePeerId;

  /// Error message if handshake failed
  final String? error;

  /// Additional metadata from the handshake
  final Map<String, dynamic> metadata;
}

/// Abstract interface for approving or rejecting connection requests
abstract interface class ConnectionApprovalHandler {
  /// Decide whether to approve a connection request
  Future<ConnectionRequestResponse> handleConnectionRequest(
    ConnectionRequest request,
  );
}

/// A simple auto-approval handler that always accepts connections
class AutoApprovalHandler implements ConnectionApprovalHandler {
  const AutoApprovalHandler();

  @override
  Future<ConnectionRequestResponse> handleConnectionRequest(
    ConnectionRequest request,
  ) async {
    return ConnectionRequestResponse.accept;
  }
}

/// A handler that always rejects connections
class RejectAllHandler implements ConnectionApprovalHandler {
  const RejectAllHandler();

  @override
  Future<ConnectionRequestResponse> handleConnectionRequest(
    ConnectionRequest request,
  ) async {
    return ConnectionRequestResponse.reject;
  }
}

/// A handler that requires manual approval through a callback
class ManualApprovalHandler implements ConnectionApprovalHandler {
  const ManualApprovalHandler(this.approvalCallback);

  final Future<ConnectionRequestResponse> Function(ConnectionRequest)
  approvalCallback;

  @override
  Future<ConnectionRequestResponse> handleConnectionRequest(
    ConnectionRequest request,
  ) {
    return approvalCallback(request);
  }
}

/// Interface for storing and retrieving peer information
abstract interface class PeerStore {
  /// Add or update a peer in the store
  Future<void> storePeer(Peer peer);

  /// Remove a peer from the store
  Future<void> removePeer(PeerId peerId);

  /// Get a peer by ID
  Future<Peer?> getPeer(PeerId peerId);

  /// Get all stored peers
  Future<List<Peer>> getAllPeers();

  /// Stream of peer updates (additions, modifications, removals)
  Stream<PeerStoreEvent> get peerUpdates;
}

/// Event emitted when the peer store changes
sealed class PeerStoreEvent {
  const PeerStoreEvent(this.peer);
  final Peer peer;
}

/// A peer was added to the store
class PeerAdded extends PeerStoreEvent {
  const PeerAdded(super.peer);
}

/// A peer was updated in the store
class PeerUpdated extends PeerStoreEvent {
  const PeerUpdated(super.peer);
}

/// A peer was removed from the store
class PeerRemoved extends PeerStoreEvent {
  const PeerRemoved(super.peer);
}

/// Interface for deciding which discovered devices to connect to
abstract interface class ConnectionPolicy {
  /// Whether to automatically connect to this discovered device
  Future<bool> shouldConnectToDevice(DiscoveredDevice device);
}

/// Auto-connect to all discovered devices
class AutoConnectPolicy implements ConnectionPolicy {
  const AutoConnectPolicy();

  @override
  Future<bool> shouldConnectToDevice(DiscoveredDevice device) async {
    return true;
  }
}

/// Never auto-connect to discovered devices
class ManualConnectPolicy implements ConnectionPolicy {
  const ManualConnectPolicy();

  @override
  Future<bool> shouldConnectToDevice(DiscoveredDevice device) async {
    return false;
  }
}

/// Use a callback to decide which devices to connect to
class PolicyBasedConnectionPolicy implements ConnectionPolicy {
  const PolicyBasedConnectionPolicy(this.shouldConnect);

  final Future<bool> Function(DiscoveredDevice) shouldConnect;

  @override
  Future<bool> shouldConnectToDevice(DiscoveredDevice device) {
    return shouldConnect(device);
  }
}

/// Configuration for the transport manager
class TransportConfig {
  const TransportConfig({
    required this.localPeerId,
    required this.protocol,
    this.handshakeProtocol = const JsonHandshakeProtocol(),
    this.approvalHandler = const AutoApprovalHandler(),
    this.connectionPolicy = const AutoConnectPolicy(),
    this.peerStore,
    this.handshakeTimeout = const Duration(seconds: 10),
  });

  /// The local peer ID
  final PeerId localPeerId;

  /// The transport protocol to use
  final TransportProtocol protocol;

  /// The handshake protocol to use (defaults to JsonHandshakeProtocol)
  final HandshakeProtocol handshakeProtocol;

  /// Handler for connection approval (defaults to AutoApprovalHandler)
  final ConnectionApprovalHandler approvalHandler;

  /// Optional policy for deciding which discovered devices to connect to
  final ConnectionPolicy? connectionPolicy;

  /// Optional peer store for persistence
  final PeerStore? peerStore;

  /// Timeout for handshake operations
  final Duration handshakeTimeout;
}
