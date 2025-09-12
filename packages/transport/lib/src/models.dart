import 'dart:typed_data';

/// Represents a unique identifier for a peer in the network.
/// This is distinct from the device address and identifies the peer application.
class PeerId {
  const PeerId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PeerId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PeerId($value)';
}

/// Represents a network address where a device can be reached.
/// This could be an IP address, Bluetooth address, etc.
class DeviceAddress {
  const DeviceAddress(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceAddress &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DeviceAddress($value)';
}

/// Status of a peer connection
enum PeerStatus {
  /// Peer is discovered but not connected
  discovered,

  /// Connection is being established
  connecting,

  /// Peer is connected and ready for communication
  connected,

  /// Connection is being closed
  disconnecting,

  /// Peer is disconnected
  disconnected,

  /// Connection failed or peer is unreachable
  failed,
}

/// Represents a peer in the network with its connection information
class Peer {
  const Peer({
    required this.id,
    required this.address,
    required this.status,
    this.metadata = const {},
    this.lastSeen,
  });

  /// Unique identifier for this peer
  final PeerId id;

  /// Network address where this peer can be reached
  final DeviceAddress address;

  /// Current connection status
  final PeerStatus status;

  /// Additional metadata about the peer (e.g., device info, capabilities)
  final Map<String, dynamic> metadata;

  /// When this peer was last seen/active
  final DateTime? lastSeen;

  /// Create a copy of this peer with updated fields
  Peer copyWith({
    PeerId? id,
    DeviceAddress? address,
    PeerStatus? status,
    Map<String, dynamic>? metadata,
    DateTime? lastSeen,
  }) {
    return Peer(
      id: id ?? this.id,
      address: address ?? this.address,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Peer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          address == other.address &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, address, status);

  @override
  String toString() => 'Peer(id: $id, address: $address, status: $status)';
}

/// Represents a message sent between peers
class TransportMessage {
  const TransportMessage({
    required this.senderId,
    required this.recipientId,
    required this.data,
    required this.timestamp,
    this.messageId,
    this.metadata = const {},
  });

  /// ID of the peer who sent this message
  final PeerId senderId;

  /// ID of the peer who should receive this message
  final PeerId recipientId;

  /// The message payload
  final Uint8List data;

  /// When this message was created
  final DateTime timestamp;

  /// Optional unique identifier for this message
  final String? messageId;

  /// Additional metadata about the message
  final Map<String, dynamic> metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransportMessage &&
          runtimeType == other.runtimeType &&
          senderId == other.senderId &&
          recipientId == other.recipientId &&
          messageId == other.messageId;

  @override
  int get hashCode => Object.hash(senderId, recipientId, messageId);

  @override
  String toString() =>
      'TransportMessage(from: $senderId, to: $recipientId, id: $messageId)';
}

/// Result of a connection attempt
enum ConnectionResult {
  /// Connection was successful
  success,

  /// Connection was rejected by the remote peer
  rejected,

  /// Connection failed due to network or protocol error
  failed,

  /// Connection timed out
  timeout,

  /// Connection was cancelled
  cancelled,
}

/// Information about a connection attempt result
class ConnectionAttemptResult {
  const ConnectionAttemptResult({
    required this.peerId,
    required this.result,
    this.error,
    this.metadata = const {},
  });

  /// The peer that was being connected to
  final PeerId peerId;

  /// The result of the connection attempt
  final ConnectionResult result;

  /// Error information if the connection failed
  final String? error;

  /// Additional metadata about the connection attempt
  final Map<String, dynamic> metadata;

  @override
  String toString() =>
      'ConnectionAttemptResult(peer: $peerId, result: $result)';
}

/// Represents an incoming connection request from a peer
class ConnectionRequest {
  const ConnectionRequest({
    required this.peerId,
    required this.address,
    required this.timestamp,
    this.metadata = const {},
  });

  /// ID of the peer requesting connection
  final PeerId peerId;

  /// Address of the requesting peer
  final DeviceAddress address;

  /// When the connection request was received
  final DateTime timestamp;

  /// Additional metadata from the connection request
  final Map<String, dynamic> metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionRequest &&
          runtimeType == other.runtimeType &&
          peerId == other.peerId &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(peerId, timestamp);

  @override
  String toString() => 'ConnectionRequest(peer: $peerId, from: $address)';
}

/// Response to a connection request
enum ConnectionRequestResponse {
  /// Accept the connection request
  accept,

  /// Reject the connection request
  reject,
}
