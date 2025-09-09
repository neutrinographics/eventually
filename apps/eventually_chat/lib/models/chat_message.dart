import 'dart:convert';
import 'dart:typed_data';
import 'package:eventually/eventually.dart';
import 'package:uuid/uuid.dart';

/// Represents a chat message stored as a block in the Merkle DAG.
///
/// Messages are content-addressed and form a DAG structure where each message
/// can reference previous messages (for replies or threading).
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final String? replyToId;
  final CID cid;
  final Block block;

  ChatMessage._({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.replyToId,
    required this.cid,
    required this.block,
  });

  /// Creates a new chat message and stores it as a block in the DAG.
  factory ChatMessage.create({
    required String senderId,
    required String senderName,
    required String content,
    DateTime? timestamp,
    String? replyToId,
  }) {
    final id = const Uuid().v4();
    final messageTimestamp = timestamp ?? DateTime.now();

    // Create the message data structure
    final messageData = {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': messageTimestamp.millisecondsSinceEpoch,
      'type': 'chat_message',
      if (replyToId != null) 'replyToId': replyToId,
    };

    // Convert to JSON and create block
    final jsonData = jsonEncode(messageData);
    final dataBytes = Uint8List.fromList(utf8.encode(jsonData));
    final block = Block.fromData(dataBytes, codec: MultiCodec.dagJson);

    return ChatMessage._(
      id: id,
      senderId: senderId,
      senderName: senderName,
      content: content,
      timestamp: messageTimestamp,
      replyToId: replyToId,
      cid: block.cid,
      block: block,
    );
  }

  /// Creates a ChatMessage from an existing block in the DAG.
  factory ChatMessage.fromBlock(Block block) {
    try {
      final jsonString = utf8.decode(block.data);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      return ChatMessage._(
        id: data['id'] as String,
        senderId: data['senderId'] as String,
        senderName: data['senderName'] as String,
        content: data['content'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          data['timestamp'] as int,
        ),
        replyToId: data['replyToId'] as String?,
        cid: block.cid,
        block: block,
      );
    } catch (e) {
      throw FormatException('Invalid chat message block: $e');
    }
  }

  /// Creates a reply to this message.
  ChatMessage createReply({
    required String senderId,
    required String senderName,
    required String content,
    DateTime? timestamp,
  }) {
    return ChatMessage.create(
      senderId: senderId,
      senderName: senderName,
      content: content,
      timestamp: timestamp,
      replyToId: id,
    );
  }

  /// Whether this message is a reply to another message.
  bool get isReply => replyToId != null;

  /// Gets the size of this message in bytes.
  int get size => block.size;

  /// Gets the content identifier for this message.
  CID get contentId => cid;

  /// Validates the message block integrity.
  bool validate() {
    return block.validate();
  }

  /// Converts the message to a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'replyToId': replyToId,
      'cid': cid.toString(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          cid == other.cid;

  @override
  int get hashCode => Object.hash(id, cid);

  @override
  String toString() {
    return 'ChatMessage(id: $id, sender: $senderName, content: ${content.substring(0, content.length.clamp(0, 50))}${content.length > 50 ? '...' : ''})';
  }
}

/// Represents a user presence announcement in the chat system.
///
/// Presence messages are stored as blocks and synchronized across peers
/// to track who is online/offline.
class UserPresence {
  final String userId;
  final String userName;
  final bool isOnline;
  final DateTime timestamp;
  final CID cid;
  final Block block;

  UserPresence._({
    required this.userId,
    required this.userName,
    required this.isOnline,
    required this.timestamp,
    required this.cid,
    required this.block,
  });

  /// Creates a new user presence announcement.
  factory UserPresence.create({
    required String userId,
    required String userName,
    required bool isOnline,
    DateTime? timestamp,
  }) {
    final presenceTimestamp = timestamp ?? DateTime.now();

    final presenceData = {
      'userId': userId,
      'userName': userName,
      'isOnline': isOnline,
      'timestamp': presenceTimestamp.millisecondsSinceEpoch,
      'type': 'user_presence',
    };

    final jsonData = jsonEncode(presenceData);
    final dataBytes = Uint8List.fromList(utf8.encode(jsonData));
    final block = Block.fromData(dataBytes, codec: MultiCodec.dagJson);

    return UserPresence._(
      userId: userId,
      userName: userName,
      isOnline: isOnline,
      timestamp: presenceTimestamp,
      cid: block.cid,
      block: block,
    );
  }

  /// Creates a UserPresence from an existing block.
  factory UserPresence.fromBlock(Block block) {
    try {
      final jsonString = utf8.decode(block.data);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      return UserPresence._(
        userId: data['userId'] as String,
        userName: data['userName'] as String,
        isOnline: data['isOnline'] as bool,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          data['timestamp'] as int,
        ),
        cid: block.cid,
        block: block,
      );
    } catch (e) {
      throw FormatException('Invalid user presence block: $e');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPresence &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          cid == other.cid;

  @override
  int get hashCode => Object.hash(userId, cid);

  @override
  String toString() {
    return 'UserPresence(userId: $userId, userName: $userName, isOnline: $isOnline)';
  }
}
