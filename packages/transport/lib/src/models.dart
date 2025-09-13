import 'dart:typed_data';

/// Exception thrown by transport protocol operations
class TransportException implements Exception {
  const TransportException(this.message, {this.cause});

  /// The error message
  final String message;

  /// The underlying cause of the exception, if any
  final Object? cause;

  @override
  String toString() =>
      'TransportException: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

class TransportDevice {
  /// Network address where this device can be reached
  final DeviceAddress address;

  /// Display name discovered during peer discovery.
  final String displayName;

  /// When this transport peer was connected.
  final DateTime connectedAt;

  /// Whether this transport peer is currently active.
  final bool isActive;

  /// Optional metadata about this transport peer.
  final Map<String, dynamic> metadata;

  /// Constructor for TransportDevice
  TransportDevice({
    required this.address,
    required this.displayName,
    required this.connectedAt,
    this.isActive = true,
    this.metadata = const {},
  });

  /// Creates a copy with modified values.
  TransportDevice copyWith({
    DeviceAddress? address,
    String? displayName,
    DateTime? connectedAt,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) {
    return TransportDevice(
      address: address ?? this.address,
      displayName: displayName ?? this.displayName,
      connectedAt: connectedAt ?? this.connectedAt,
      isActive: isActive ?? this.isActive,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'TransportDevice(address: $address, displayName: $displayName, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TransportDevice) return false;
    return address == other.address;
  }

  @override
  int get hashCode => address.hashCode;
}

/// Represents a discovered device on the network (before peer identification)
@Deprecated('Use TransportDevice instead')
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.address,
    required this.displayName,
    required this.discoveredAt,
    this.metadata = const {},
  });

  /// Network address where this device can be reached
  final DeviceAddress address;

  /// Human-readable name for this device (e.g., "John's iPhone")
  final String displayName;

  /// When this device was discovered
  final DateTime discoveredAt;

  /// Additional metadata about the device (e.g., capabilities, service info)
  final Map<String, dynamic> metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredDevice &&
          runtimeType == other.runtimeType &&
          address == other.address &&
          displayName == other.displayName;

  @override
  int get hashCode => Object.hash(address, displayName);

  @override
  String toString() => 'DiscoveredDevice($displayName at $address)';
}

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

  /// Additional metadata about the message
  final Map<String, dynamic> metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransportMessage &&
          runtimeType == other.runtimeType &&
          senderId == other.senderId &&
          recipientId == other.recipientId &&
          data == other.data &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(senderId, recipientId, data, timestamp);

  @override
  String toString() => 'TransportMessage(from: $senderId, to: $recipientId)';
}
