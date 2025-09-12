import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../transport.dart';

/// Exception thrown when TCP transport operations fail.
class TcpTransportException implements Exception {
  const TcpTransportException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('TcpTransportException: $message');
    if (cause != null) {
      buffer.write(' (caused by: $cause)');
    }
    return buffer.toString();
  }
}

/// Transport implementation using TCP sockets for peer-to-peer communication.
///
/// This transport is suitable for local network communication and can work
/// over WiFi or Ethernet connections. It supports both server and client modes.
class TcpTransport implements Transport {
  /// The local port to listen on.
  final int port;

  /// The local display name.
  final String displayName;

  /// Optional interface to bind to (defaults to any interface).
  final InternetAddress? bindAddress;

  // Internal state
  bool _isInitialized = false;
  ServerSocket? _serverSocket;

  final Map<String, TransportPeer> _connectedPeers = {};
  final Map<String, Socket> _connections = {};
  final Map<String, StreamSubscription> _subscriptions = {};

  final StreamController<IncomingBytes> _incomingBytesController =
      StreamController<IncomingBytes>.broadcast();

  /// Creates a TCP transport with the specified configuration.
  TcpTransport({
    required this.port,
    required this.displayName,
    this.bindAddress,
  });

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final address = bindAddress ?? InternetAddress.anyIPv4;
      _serverSocket = await ServerSocket.bind(address, port);

      _serverSocket!.listen(_handleIncomingConnection);
      _isInitialized = true;
    } catch (e) {
      throw TcpTransportException(
        'Failed to initialize TCP transport on port $port',
        cause: e,
      );
    }
  }

  @override
  Future<void> shutdown() async {
    if (!_isInitialized) return;

    try {
      // Close all connections
      for (final subscription in _subscriptions.values) {
        subscription.cancel();
      }
      _subscriptions.clear();

      for (final socket in _connections.values) {
        socket.destroy();
      }
      _connections.clear();

      // Close server socket
      await _serverSocket?.close();
      _serverSocket = null;

      _connectedPeers.clear();
      _isInitialized = false;

      await _incomingBytesController.close();
    } catch (e) {
      throw TcpTransportException('Failed to shutdown TCP transport', cause: e);
    }
  }

  @override
  Future<List<TransportPeer>> discoverPeers({Duration? timeout}) async {
    if (!_isInitialized) {
      throw const TcpTransportException('Transport not initialized');
    }

    // TCP transport doesn't have built-in discovery, so we scan common ports
    // on the local network. This is a simple implementation - in production
    // you might use mDNS, broadcast, or a service registry.

    final discoveredPeers = <TransportPeer>[];
    final scanTimeout = timeout ?? const Duration(seconds: 5);

    try {
      // Get local network addresses to scan
      final interfaces = await NetworkInterface.list();
      final subnetsToScan = <String>{};

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
            // Extract subnet (assumes /24 for simplicity)
            final parts = address.address.split('.');
            if (parts.length == 4) {
              final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
              subnetsToScan.add(subnet);
            }
          }
        }
      }

      // Scan each subnet
      final futures = <Future>[];
      for (final subnet in subnetsToScan) {
        for (int i = 1; i < 255; i++) {
          final targetAddress = '$subnet.$i';
          futures.add(_scanAddress(targetAddress, discoveredPeers));
        }
      }

      // Wait for all scans to complete or timeout
      await Future.wait(futures).timeout(scanTimeout);
    } catch (e) {
      // Discovery failures are not critical, just return what we found
    }

    return discoveredPeers;
  }

  @override
  Future<void> sendBytes(
    TransportPeer peer,
    Uint8List bytes, {
    Duration? timeout,
  }) async {
    if (!_isInitialized) {
      throw const TcpTransportException('Transport not initialized');
    }

    final socket = _connections[peer.address.value];
    if (socket == null) {
      throw TcpTransportException('Not connected to peer: ${peer.address}');
    }

    try {
      // Send length prefix followed by data
      final lengthBytes = Uint8List(4);
      final byteData = ByteData.view(lengthBytes.buffer);
      byteData.setUint32(0, bytes.length, Endian.big);

      socket.add(lengthBytes);
      socket.add(bytes);
      await socket.flush();
    } catch (e) {
      throw TcpTransportException(
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

    // Check if we have an active connection
    final socket = _connections[transportPeer.address.value];
    if (socket != null) {
      return _connectedPeers.containsKey(transportPeer.address.value);
    }

    // Try to connect briefly to test reachability
    try {
      final parts = transportPeer.address.value.split(':');
      if (parts.length != 2) return false;

      final host = parts[0];
      final port = int.tryParse(parts[1]);
      if (port == null) return false;

      final socket = await Socket.connect(
        host,
        port,
      ).timeout(const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Manually connect to a peer at the specified address.
  Future<void> connectToPeer(String host, int port) async {
    if (!_isInitialized) {
      throw const TcpTransportException('Transport not initialized');
    }

    final addressKey = '$host:$port';
    if (_connections.containsKey(addressKey)) {
      return; // Already connected
    }

    try {
      final socket = await Socket.connect(host, port);
      _handleConnection(socket, isIncoming: false);
    } catch (e) {
      throw TcpTransportException('Failed to connect to $host:$port', cause: e);
    }
  }

  // Private helper methods

  void _handleIncomingConnection(Socket socket) {
    _handleConnection(socket, isIncoming: true);
  }

  void _handleConnection(Socket socket, {required bool isIncoming}) {
    final remoteAddress = socket.remoteAddress.address;
    final remotePort = socket.remotePort;
    final addressKey = '$remoteAddress:$remotePort';

    final peer = TransportPeer(
      address: TransportPeerAddress(addressKey),
      displayName: 'TCP Peer $remoteAddress',
      protocol: 'tcp',
      metadata: {
        'host': remoteAddress,
        'port': remotePort,
        'incoming': isIncoming,
        'connected_at': DateTime.now().toIso8601String(),
      },
    );

    _connectedPeers[addressKey] = peer;
    _connections[addressKey] = socket;

    // Set up data handling with framing
    final subscription = socket.listen(
      (data) => _handleData(peer, data),
      onError: (error) => _handleConnectionError(peer, error),
      onDone: () => _handleConnectionClosed(peer),
    );

    _subscriptions[addressKey] = subscription;
  }

  final Map<String, List<int>> _buffers = {};
  final Map<String, int?> _expectedLengths = {};

  void _handleData(TransportPeer peer, List<int> data) {
    final addressKey = peer.address.value;

    // Add data to buffer
    _buffers[addressKey] ??= <int>[];
    _buffers[addressKey]!.addAll(data);

    // Process complete messages
    while (true) {
      final buffer = _buffers[addressKey]!;
      var expectedLength = _expectedLengths[addressKey];

      // If we don't know the expected length, try to read it
      if (expectedLength == null) {
        if (buffer.length < 4) break; // Need at least 4 bytes for length

        final lengthBytes = Uint8List.fromList(buffer.take(4).toList());
        final byteData = ByteData.view(lengthBytes.buffer);
        expectedLength = byteData.getUint32(0, Endian.big);
        _expectedLengths[addressKey] = expectedLength;

        // Remove length prefix from buffer
        buffer.removeRange(0, 4);
      }

      // Check if we have a complete message
      if (buffer.length < expectedLength) break;

      // Extract the complete message
      final messageBytes = Uint8List.fromList(
        buffer.take(expectedLength).toList(),
      );
      buffer.removeRange(0, expectedLength);
      _expectedLengths[addressKey] = null;

      // Emit the incoming bytes
      final incomingBytes = IncomingBytes(peer, messageBytes, DateTime.now());
      _incomingBytesController.add(incomingBytes);
    }
  }

  void _handleConnectionError(TransportPeer peer, dynamic error) {
    final addressKey = peer.address.value;
    _cleanupConnection(addressKey);
  }

  void _handleConnectionClosed(TransportPeer peer) {
    final addressKey = peer.address.value;
    _cleanupConnection(addressKey);
  }

  void _cleanupConnection(String addressKey) {
    _subscriptions[addressKey]?.cancel();
    _subscriptions.remove(addressKey);
    _connections[addressKey]?.destroy();
    _connections.remove(addressKey);
    _connectedPeers.remove(addressKey);
    _buffers.remove(addressKey);
    _expectedLengths.remove(addressKey);
  }

  Future<void> _scanAddress(
    String address,
    List<TransportPeer> discovered,
  ) async {
    try {
      final socket = await Socket.connect(
        address,
        port,
      ).timeout(const Duration(milliseconds: 500));

      final peer = TransportPeer(
        address: TransportPeerAddress('$address:$port'),
        displayName: 'TCP Peer $address',
        protocol: 'tcp',
        metadata: {
          'host': address,
          'port': port,
          'discovered_at': DateTime.now().toIso8601String(),
        },
      );

      discovered.add(peer);
      socket.destroy();
    } catch (e) {
      // Address not reachable, ignore
    }
  }

  /// Gets all currently connected peers.
  List<TransportPeer> get connectedPeers => _connectedPeers.values.toList();

  /// Gets the local address this transport is listening on.
  String? get localAddress => _serverSocket?.address.address;

  /// Gets the port this transport is listening on.
  int? get localPort => _serverSocket?.port;
}
