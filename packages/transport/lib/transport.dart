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
///   // handshakeProtocol: JsonHandshakeProtocol(), // Optional - this is the default
///   // approvalHandler: AutoApprovalHandler(),     // Optional - this is the default
/// );
///
/// final transport = TransportManager(config);
///
/// // Application only sees peers - device discovery is handled internally
/// // Peers appear automatically when devices are discovered and connected
/// transport.peerUpdates.listen((peer) {
///   print('Peer ${peer.id.value} is now ${peer.status}');
/// });
///
/// transport.messagesReceived.listen((message) {
///   final text = String.fromCharCodes(message.data);
///   print('Received: $text from ${message.senderId.value}');
/// });
///
/// // Start the transport (starts periodic discovery and automatic handshaking)
/// await transport.start();
///
/// // Wait for peers to be discovered automatically
/// transport.peerUpdates.listen((peer) {
///   if (peer.status == PeerStatus.connected) {
///     print('New peer connected: ${peer.id.value}');
///     // Send a message to the connected peer
///     final message = TransportMessage(
///       senderId: config.localPeerId,
///       recipientId: peer.id,
///       data: Uint8List.fromList('Hello!'.codeUnits),
///       timestamp: DateTime.now(),
///     );
///     transport.sendMessage(message);
///   }
/// });
///
/// // Peers are discovered and connected automatically - no manual connection needed
/// ```
library transport;

export 'src/models.dart';
export 'src/interfaces.dart';
export 'src/transport_manager.dart';

export 'src/default_implementations.dart';
