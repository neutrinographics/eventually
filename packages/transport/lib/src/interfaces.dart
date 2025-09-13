import 'dart:async';
import 'dart:typed_data';

import 'models.dart';
import 'default_implementations.dart';

/// Abstract interface for low-level transport protocols (e.g., TCP, WebSocket, Bluetooth)
/// Includes connection management, device discovery, and direct data transmission
abstract interface class TransportProtocol {
  /// Initializes the transport layer.
  ///
  /// This should set up any necessary resources (servers, connections, etc.)
  /// and prepare the transport to handle incoming and outgoing messages.
  ///
  /// Throws [TransportException] if initialization fails.
  Future<void> initialize();

  /// Shuts down the transport layer.
  ///
  /// This should cleanly close any resources and stop accepting new
  /// connections or messages. After calling this method, the transport
  /// should not be used.
  Future<void> shutdown();

  /// Send data directly to a device address
  /// Throws [TransportException] if the operation fails or times out.
  Future<void> sendData(
    DeviceAddress address,
    Uint8List data, {
    Duration? timeout,
  });

  /// Stream of incoming data with sender address information
  Stream<IncomingData> get incomingData;

  /// Stream of connection events (connected/disconnected from addresses)
  // Stream<ConnectionEvent> get connectionEvents;

  /// Stream of newly discovered devices.
  /// You must [connect] to a discovered device before you can communicate with it.
  // Stream<DiscoveredDevice> get devicesDiscovered;

  /// Stream of devices that are no longer available
  // Stream<DeviceAddress> get devicesLost;

  /// Discovers and returns available transport devices in the network.
  ///
  /// This method is used for device discovery and maintenance. The exact
  /// mechanism depends on the transport implementation (could be multicast,
  /// centralized discovery service, etc.).
  ///
  /// Returns a list of discovered transport devices. May return an empty list if
  /// no devices are currently available.
  Future<List<TransportDevice>> discoverDevices();
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

/// Configuration for the transport manager
class TransportConfig {
  const TransportConfig({
    required this.localPeerId,
    required this.protocol,
    this.handshakeProtocol = const JsonHandshakeProtocol(),
    this.peerStore,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.discoveryInterval = const Duration(seconds: 30),
  });

  /// The local peer ID
  final PeerId localPeerId;

  /// The transport protocol to use
  final TransportProtocol protocol;

  /// The handshake protocol to use (defaults to JsonHandshakeProtocol)
  final HandshakeProtocol handshakeProtocol;

  /// Optional peer store for persistence
  final PeerStore? peerStore;

  /// Timeout for handshake operations
  final Duration handshakeTimeout;

  /// How often to discover devices (defaults to 30 seconds)
  final Duration discoveryInterval;
}
