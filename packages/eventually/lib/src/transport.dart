import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Type-safe address for transport devices.
/// For example, this could be a MAC address, IP address, or any other
/// unique identifier used by the transport protocol.
@immutable
class TransportDeviceAddress {
  /// The underlying string address.
  final String value;

  /// Creates a transport peer address.
  const TransportDeviceAddress(this.value);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TransportDeviceAddress) return false;
    return value == other.value;
  }

  @override
  int get hashCode => value.hashCode;
}

/// Transport-level device representation.
/// This represents a remote device at the transport layer.
@immutable
class TransportDevice {
  final TransportDeviceAddress address;

  /// The advertised display name of this device.
  /// This is typically a human-readable name.
  final String displayName;

  /// Transport protocol identifier.
  /// Examples: "nearby_connections", "tcp", "udp", "bluetooth", "websocket"
  final String protocol;

  /// When this transport peer was connected.
  final DateTime connectedAt;

  /// Whether this transport peer is currently active.
  final bool isActive;

  /// Optional metadata about this transport peer.
  final Map<String, dynamic> metadata;

  TransportDevice({
    required this.address,
    required this.displayName,
    required this.protocol,
    DateTime? connectedAt,
    this.isActive = true,
    this.metadata = const {},
  }) : connectedAt = connectedAt ?? DateTime.now();

  /// Creates a copy with modified values.
  TransportDevice copyWith({
    TransportDeviceAddress? address,
    String? displayName,
    String? protocol,
    DateTime? connectedAt,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) {
    return TransportDevice(
      address: address ?? this.address,
      displayName: displayName ?? this.displayName,
      protocol: protocol ?? this.protocol,
      connectedAt: connectedAt ?? this.connectedAt,
      isActive: isActive ?? this.isActive,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'TransportPeer(address: $address, displayName: $displayName, protocol: $protocol, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TransportDevice) return false;
    return address == other.address && protocol == other.protocol;
  }

  @override
  int get hashCode => Object.hash(address, protocol);
}

/// Abstract interface for transport layer implementations.
///
/// This interface defines the methods needed to communicate with other
/// nodes in the network. Implementations can use different
/// protocols (nearby, HTTP, TCP, UDP, etc.) while providing a consistent API
/// for the sync protocol.
abstract class Transport {
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

  /// Discovers and returns available transport peers in the network.
  ///
  /// This method is used for peer discovery and maintenance. The exact
  /// mechanism depends on the transport implementation (could be multicast,
  /// centralized discovery service, etc.).
  ///
  /// Returns a list of discovered transport peers. May return an empty list if
  /// no peers are currently available.
  ///
  /// Throws [TransportException] if discovery fails.
  Future<List<TransportDevice>> discoverDevices({Duration? timeout});

  /// Sends bytes to a specific transport peer.
  ///
  /// This method is used to send messages to other nodes in the network.
  /// The exact mechanism depends on the transport implementation (could be
  /// direct socket connection, HTTP request, etc.).
  ///
  /// Throws [TransportException] if sending fails.
  Future<void> sendBytes(OutgoingBytes outgoingBytes, {Duration? timeout});

  /// Receives bytes from transport peers.
  ///
  /// This method is used to receive bytes from other nodes in the network.
  /// The exact mechanism depends on the transport implementation (could be
  /// direct socket connection, HTTP request, etc.).
  Stream<IncomingBytes> get incomingBytes;

  /// Checks if a transport peer is currently reachable.
  ///
  /// This can be used for peer health checking and maintenance.
  /// The implementation should be lightweight and fast.
  Future<bool> isPeerReachable(TransportDevice transportPeer);
}

@immutable
class IncomingBytes {
  final TransportDevice device;
  final Uint8List bytes;
  final DateTime receivedAt;

  IncomingBytes(this.device, this.bytes, this.receivedAt);
}

@immutable
class OutgoingBytes {
  final TransportDevice device;
  final Uint8List bytes;

  OutgoingBytes(this.device, this.bytes);
}

/// Exception thrown when transport operations fail.
class TransportException implements Exception {
  const TransportException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('TransportException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}
