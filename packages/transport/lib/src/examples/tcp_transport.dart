import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../interfaces.dart';
import '../models.dart';

/// Example TCP-based transport protocol implementation
class TcpTransportProtocol implements TransportProtocol {
  TcpTransportProtocol();

  ServerSocket? _serverSocket;
  final StreamController<IncomingConnectionAttempt> _incomingController =
      StreamController<IncomingConnectionAttempt>.broadcast();

  @override
  Stream<IncomingConnectionAttempt> get incomingConnections =>
      _incomingController.stream;

  @override
  bool get isListening => _serverSocket != null;

  @override
  Future<void> startListening(DeviceAddress address) async {
    if (isListening) return;

    // Parse address (expected format: "ip:port")
    final parts = address.value.split(':');
    if (parts.length != 2) {
      throw ArgumentError('Invalid TCP address format. Expected "ip:port"');
    }

    final host = parts[0];
    final port = int.tryParse(parts[1]);
    if (port == null) {
      throw ArgumentError('Invalid port number: ${parts[1]}');
    }

    try {
      _serverSocket = await ServerSocket.bind(
        host == '0.0.0.0' ? InternetAddress.anyIPv4 : InternetAddress(host),
        port,
      );

      _serverSocket!.listen(_handleIncomingSocket);
    } catch (e) {
      _serverSocket = null;
      rethrow;
    }
  }

  @override
  Future<void> stopListening() async {
    if (!isListening) return;

    await _serverSocket!.close();
    _serverSocket = null;
  }

  @override
  Future<TransportConnection?> connect(DeviceAddress address) async {
    // Parse address (expected format: "ip:port")
    final parts = address.value.split(':');
    if (parts.length != 2) {
      throw ArgumentError('Invalid TCP address format. Expected "ip:port"');
    }

    final host = parts[0];
    final port = int.tryParse(parts[1]);
    if (port == null) {
      throw ArgumentError('Invalid port number: ${parts[1]}');
    }

    try {
      final socket = await Socket.connect(host, port);
      return TcpTransportConnection(socket, DeviceAddress('$host:$port'));
    } catch (e) {
      return null;
    }
  }

  void _handleIncomingSocket(Socket socket) {
    final remoteAddress = DeviceAddress(
      '${socket.remoteAddress.address}:${socket.remotePort}',
    );
    final connection = TcpTransportConnection(socket, remoteAddress);
    final attempt = IncomingConnectionAttempt(
      connection: connection,
      address: remoteAddress,
    );

    _incomingController.add(attempt);
  }

  /// Dispose of this transport protocol and clean up resources
  Future<void> dispose() async {
    await stopListening();
    await _incomingController.close();
  }
}

/// TCP implementation of TransportConnection
class TcpTransportConnection implements TransportConnection {
  TcpTransportConnection(this._socket, this.remoteAddress) {
    _socket.listen(
      _dataController.add,
      onError: (error) {
        _dataController.addError(error);
        close();
      },
      onDone: () {
        _connectionClosedController.add(null);
        _isOpen = false;
      },
    );
  }

  final Socket _socket;
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();
  final StreamController<void> _connectionClosedController =
      StreamController<void>.broadcast();

  bool _isOpen = true;

  @override
  final DeviceAddress remoteAddress;

  @override
  Stream<Uint8List> get dataReceived => _dataController.stream;

  @override
  Stream<void> get connectionClosed => _connectionClosedController.stream;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> send(Uint8List data) async {
    if (!isOpen) throw StateError('Connection is closed');

    // Add length prefix to help with message framing
    final lengthBytes = Uint8List(4);
    lengthBytes.buffer.asByteData().setUint32(0, data.length);

    _socket.add(lengthBytes);
    _socket.add(data);
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;

    try {
      await _socket.close();
    } finally {
      await _dataController.close();
      await _connectionClosedController.close();
    }
  }
}

/// Helper class to handle TCP message framing
class TcpMessageFramer {
  TcpMessageFramer(this.onMessage);

  final void Function(Uint8List) onMessage;

  Uint8List? _buffer;
  int? _expectedLength;

  void processData(Uint8List data) {
    if (_buffer == null) {
      _buffer = Uint8List.fromList(data);
    } else {
      // Append new data to existing buffer
      final combined = Uint8List(_buffer!.length + data.length);
      combined.setRange(0, _buffer!.length, _buffer!);
      combined.setRange(_buffer!.length, combined.length, data);
      _buffer = combined;
    }

    _processBuffer();
  }

  void _processBuffer() {
    while (_buffer != null && _buffer!.length >= 4) {
      // Read message length if we don't have it yet
      _expectedLength ??= _buffer!.buffer.asByteData().getUint32(0);

      // Check if we have the complete message
      if (_buffer!.length >= 4 + _expectedLength!) {
        // Extract the message
        final messageData = _buffer!.sublist(4, 4 + _expectedLength!);
        onMessage(messageData);

        // Remove the processed message from buffer
        if (_buffer!.length == 4 + _expectedLength!) {
          _buffer = null;
        } else {
          _buffer = _buffer!.sublist(4 + _expectedLength!);
        }

        _expectedLength = null;
      } else {
        // Not enough data yet
        break;
      }
    }
  }
}
