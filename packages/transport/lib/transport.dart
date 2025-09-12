/// A generic transport library for handling peer-to-peer network connections
/// with customizable protocols and handshakes.
///
/// This library provides a high-level interface for managing network connections
/// between peers, with support for:
/// - Peer discovery and management
/// - Connection approval/rejection mechanisms
/// - Distinction between device addresses and peer IDs
/// - Live updates for peer status and messages
/// - Customizable handshake protocols
/// - Pluggable transport protocols
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:transport/transport.dart';
///
/// // Create a transport manager
/// final config = TransportConfig(
///   localPeerId: PeerId('my-peer-id'),
///   protocol: MyTransportProtocol(), // Your transport implementation
///   handshakeProtocol: JsonHandshakeProtocol(),
///   approvalHandler: AutoApprovalHandler(),
/// );
///
/// final transport = TransportManager(config);
///
/// // Listen for peer updates and messages
/// transport.peerUpdates.listen((peer) {
///   print('Peer update: ${peer.id} is now ${peer.status}');
/// });
///
/// transport.messagesReceived.listen((message) {
///   print('Received message from ${message.senderId}');
/// });
///
/// // Start the transport
/// await transport.start();
///
/// // Connect to a peer
/// final result = await transport.connectToPeer(PeerId('other-peer'));
/// if (result.result == ConnectionResult.success) {
///   // Send a message
///   final message = TransportMessage(
///     senderId: config.localPeerId,
///     recipientId: PeerId('other-peer'),
///     data: Uint8List.fromList('Hello!'.codeUnits),
///     timestamp: DateTime.now(),
///   );
///   await transport.sendMessage(message);
/// }
/// ```
library transport;

export 'src/models.dart';
export 'src/interfaces.dart';
export 'src/transport_manager.dart';
export 'src/default_implementations.dart';
