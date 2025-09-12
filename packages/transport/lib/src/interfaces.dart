import 'dart:async';
import 'dart:typed_data';

import 'models.dart';

/// Abstract interface for low-level transport protocols (e.g., TCP, WebSocket, Bluetooth)
abstract interface class TransportProtocol {
  /// Start listening for incoming connections
  Future<void> startListening();

  /// Stop listening for incoming connections
  Future<void> stopListening();

  /// Attempt to connect to a peer at the given address
  Future<TransportConnection?> connect(DeviceAddress address);

  /// Stream of incoming connection attempts
  Stream<IncomingConnectionAttempt> get incomingConnections;

  /// Whether this transport is currently listening for connections
  bool get isListening;
}

/// Represents an incoming connection attempt from a remote peer
class IncomingConnectionAttempt {
  const IncomingConnectionAttempt({
    required this.connection,
    required this.address,
  });

  /// The connection that was established
  final TransportConnection connection;

  /// The address the connection came from
  final DeviceAddress address;
}

/// Abstract interface for a low-level transport connection
abstract interface class TransportConnection {
  /// Send raw data over this connection
  Future<void> send(Uint8List data);

  /// Close this connection
  Future<void> close();

  /// Stream of raw data received over this connection
  Stream<Uint8List> get dataReceived;

  /// Stream that emits when the connection is closed
  Stream<void> get connectionClosed;

  /// Whether this connection is currently open
  bool get isOpen;

  /// The remote address of this connection
  DeviceAddress get remoteAddress;
}

/// Abstract interface for handling the handshake process between peers
abstract interface class HandshakeProtocol {
  /// Perform a handshake as the initiator of the connection
  Future<HandshakeResult> initiateHandshake(
    TransportConnection connection,
    PeerId localPeerId,
  );

  /// Handle an incoming handshake as the responder
  Future<HandshakeResult> respondToHandshake(
    TransportConnection connection,
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

/// Interface for peer discovery mechanisms
abstract interface class PeerDiscovery {
  /// Start discovering peers
  Future<void> startDiscovery();

  /// Stop discovering peers
  Future<void> stopDiscovery();

  /// Stream of discovered peers
  Stream<Peer> get peersDiscovered;

  /// Stream of peers that are no longer available
  Stream<Peer> get peersLost;

  /// Whether discovery is currently active
  bool get isDiscovering;
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
    required this.handshakeProtocol,
    required this.approvalHandler,
    this.peerDiscovery,
    this.peerStore,
    this.connectionTimeout = const Duration(seconds: 30),
    this.handshakeTimeout = const Duration(seconds: 10),
    this.maxConnections = 100,
  });

  /// The local peer ID
  final PeerId localPeerId;

  /// The transport protocol to use
  final TransportProtocol protocol;

  /// The handshake protocol to use
  final HandshakeProtocol handshakeProtocol;

  /// Handler for connection approval
  final ConnectionApprovalHandler approvalHandler;

  /// Optional peer discovery mechanism
  final PeerDiscovery? peerDiscovery;

  /// Optional peer store for persistence
  final PeerStore? peerStore;

  /// Timeout for connection attempts
  final Duration connectionTimeout;

  /// Timeout for handshake operations
  final Duration handshakeTimeout;

  /// Maximum number of concurrent connections
  final int maxConnections;
}
