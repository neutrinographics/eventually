import 'package:meta/meta.dart';

/// Represents a transport endpoint for establishing connections.
///
/// This is the transport-layer abstraction that contains only the information
/// needed to establish a physical connection (address, protocol info, etc.).
/// The application-layer peer identity is discovered after connection.
@immutable
class TransportEndpoint {
  /// Creates a transport endpoint with the given address and protocol.
  const TransportEndpoint({
    required this.address,
    required this.protocol,
    this.metadata = const {},
  });

  /// Network address or identifier for this endpoint.
  /// Examples: "192.168.1.100:8080", "bluetooth:AA:BB:CC:DD:EE:FF",
  /// "nearby:endpoint123", "websocket://example.com/peer"
  final String address;

  /// Transport protocol identifier.
  /// Examples: "tcp", "udp", "bluetooth", "nearby", "websocket"
  final String protocol;

  /// Additional transport-specific metadata.
  /// May contain protocol-specific information like connection parameters,
  /// encryption settings, etc.
  final Map<String, dynamic> metadata;

  /// Creates a copy of this endpoint with updated properties.
  TransportEndpoint copyWith({
    String? address,
    String? protocol,
    Map<String, dynamic>? metadata,
  }) {
    return TransportEndpoint(
      address: address ?? this.address,
      protocol: protocol ?? this.protocol,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransportEndpoint &&
          runtimeType == other.runtimeType &&
          address == other.address &&
          protocol == other.protocol &&
          metadata == other.metadata;

  @override
  int get hashCode => Object.hash(address, protocol, metadata);

  @override
  String toString() =>
      'TransportEndpoint(protocol: $protocol, address: $address)';
}

/// Represents an active transport connection to an endpoint.
///
/// This handles the low-level transport communication before
/// application-layer peer identity is established.
abstract interface class TransportConnection {
  /// The endpoint this connection is established with.
  TransportEndpoint get endpoint;

  /// Whether this transport connection is currently active.
  bool get isConnected;

  /// Stream of raw data received from the endpoint.
  Stream<List<int>> get dataStream;

  /// Establishes the transport connection.
  Future<void> connect();

  /// Closes the transport connection.
  Future<void> disconnect();

  /// Sends raw data through the transport.
  Future<void> sendData(List<int> data);

  /// Gets transport-specific connection info.
  Map<String, dynamic> getConnectionInfo();
}

/// Manages transport-level connections to endpoints.
///
/// This is responsible only for establishing and managing transport
/// connections. Application-layer peer discovery happens after
/// transport connection is established.
abstract interface class TransportManager {
  /// All currently connected transport endpoints.
  Iterable<TransportEndpoint> get connectedEndpoints;

  /// Stream of transport connection events.
  Stream<TransportEvent> get transportEvents;

  /// Connects to a transport endpoint.
  Future<TransportConnection> connect(TransportEndpoint endpoint);

  /// Disconnects from a transport endpoint.
  Future<void> disconnect(String endpointAddress);

  /// Disconnects from all endpoints.
  Future<void> disconnectAll();

  /// Starts discovering available endpoints.
  Future<void> startDiscovery();

  /// Stops endpoint discovery.
  Future<void> stopDiscovery();

  /// Gets transport-specific statistics.
  Future<TransportStats> getStats();
}

/// Events related to transport connections.
@immutable
sealed class TransportEvent {
  const TransportEvent({required this.endpoint, required this.timestamp});

  final TransportEndpoint endpoint;
  final DateTime timestamp;
}

/// Event when a transport endpoint is discovered.
@immutable
final class EndpointDiscovered extends TransportEvent {
  const EndpointDiscovered({required super.endpoint, required super.timestamp});
}

/// Event when a transport connection is established.
@immutable
final class TransportConnected extends TransportEvent {
  const TransportConnected({required super.endpoint, required super.timestamp});
}

/// Event when a transport connection is closed.
@immutable
final class TransportDisconnected extends TransportEvent {
  const TransportDisconnected({
    required super.endpoint,
    required super.timestamp,
    this.reason,
  });

  final String? reason;
}

/// Event when data is received over a transport connection.
@immutable
final class TransportDataReceived extends TransportEvent {
  const TransportDataReceived({
    required super.endpoint,
    required super.timestamp,
    required this.data,
  });

  final List<int> data;
}

/// Statistics about transport connections.
@immutable
class TransportStats {
  const TransportStats({
    required this.totalEndpoints,
    required this.connectedEndpoints,
    required this.totalBytesReceived,
    required this.totalBytesSent,
    this.protocolStats = const {},
  });

  final int totalEndpoints;
  final int connectedEndpoints;
  final int totalBytesReceived;
  final int totalBytesSent;
  final Map<String, dynamic> protocolStats;

  @override
  String toString() =>
      'TransportStats('
      'endpoints: $connectedEndpoints/$totalEndpoints, '
      'bytes: ${totalBytesReceived + totalBytesSent}'
      ')';
}

/// Exception thrown when transport operations fail.
class TransportException implements Exception {
  const TransportException(this.message, {this.endpoint, this.cause});

  final String message;
  final TransportEndpoint? endpoint;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('TransportException: $message');
    if (endpoint != null) {
      buffer.write(' (endpoint: ${endpoint!.address})');
    }
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}

/// Exception thrown when transport connection fails.
class TransportConnectionException extends TransportException {
  const TransportConnectionException(
    String message, {
    super.endpoint,
    super.cause,
  }) : super(message);
}
