import 'package:eventually/eventually.dart';
import 'package:transport/transport.dart';

/// Represents a peer in the chat system.
///
/// Peers are other users who are participating in the chat network.
/// Each peer has a unique ID, display name, and connection status.
class ChatPeer {
  final PeerId id;
  final String name;
  final DateTime connectedAt;
  final ChatPeerStatus status;
  final bool isOnline;
  final DateTime? lastSeen;
  final Set<CID> knownBlocks;

  ChatPeer({
    required this.id,
    required this.name,
    DateTime? connectedAt,
    this.status = ChatPeerStatus.connected,
    this.isOnline = true,
    this.lastSeen,
    Set<CID>? knownBlocks,
  }) : connectedAt = connectedAt ?? DateTime.now(),
       knownBlocks = knownBlocks ?? <CID>{};

  /// Creates a peer from a transport library Peer object.
  factory ChatPeer.fromTransportPeer(
    Peer transportPeer, {
    String? name,
    ChatPeerStatus? status,
    bool? isOnline,
    DateTime? lastSeen,
    Set<CID>? knownBlocks,
  }) {
    final displayName =
        name ?? transportPeer.metadata['displayName'] as String? ?? 'Unknown';

    return ChatPeer(
      id: transportPeer.id,
      name: displayName,
      status: status ?? _mapPeerStatus(transportPeer.status),
      isOnline: isOnline ?? (transportPeer.status == PeerStatus.connected),
      lastSeen: lastSeen ?? transportPeer.lastSeen,
      knownBlocks: knownBlocks,
    );
  }

  /// Maps transport peer status to chat peer status
  static ChatPeerStatus _mapPeerStatus(PeerStatus transportStatus) {
    switch (transportStatus) {
      case PeerStatus.discovered:
        return ChatPeerStatus.discovered;
      case PeerStatus.connecting:
        return ChatPeerStatus.connecting;
      case PeerStatus.connected:
        return ChatPeerStatus.connected;
      case PeerStatus.disconnecting:
      case PeerStatus.disconnected:
        return ChatPeerStatus.disconnected;
      case PeerStatus.failed:
        return ChatPeerStatus.failed;
    }
  }

  /// Creates a copy of this peer with updated properties.
  ChatPeer copyWith({
    PeerId? id,
    String? name,
    DateTime? connectedAt,
    ChatPeerStatus? status,
    bool? isOnline,
    DateTime? lastSeen,
    Set<CID>? knownBlocks,
  }) {
    return ChatPeer(
      id: id ?? this.id,
      name: name ?? this.name,
      connectedAt: connectedAt ?? this.connectedAt,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      knownBlocks: knownBlocks ?? Set<CID>.from(this.knownBlocks),
    );
  }

  /// Marks this peer as having a specific block.
  ChatPeer withKnownBlock(CID cid) {
    final newKnownBlocks = Set<CID>.from(knownBlocks)..add(cid);
    return copyWith(knownBlocks: newKnownBlocks);
  }

  /// Marks this peer as having multiple blocks.
  ChatPeer withKnownBlocks(Set<CID> cids) {
    final newKnownBlocks = Set<CID>.from(knownBlocks)..addAll(cids);
    return copyWith(knownBlocks: newKnownBlocks);
  }

  /// Whether this peer is known to have a specific block.
  bool hasBlock(CID cid) {
    return knownBlocks.contains(cid);
  }

  /// Gets the number of blocks this peer is known to have.
  int get knownBlockCount => knownBlocks.length;

  /// Whether this peer is currently active (connected and online).
  bool get isActive => status == ChatPeerStatus.connected && isOnline;

  /// Gets a display-friendly connection duration.
  Duration get connectionDuration {
    return DateTime.now().difference(connectedAt);
  }

  /// Gets a display-friendly last seen duration (if offline).
  Duration? get lastSeenDuration {
    if (lastSeen == null) return null;
    return DateTime.now().difference(lastSeen!);
  }

  /// Converts the peer to JSON for serialization.
  Map<String, dynamic> toJson() {
    return {
      'id': id.value,
      'name': name,
      'connectedAt': connectedAt.millisecondsSinceEpoch,
      'status': status.name,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'knownBlocks': knownBlocks.map((cid) => cid.toString()).toList(),
    };
  }

  /// Creates a peer from JSON data.
  factory ChatPeer.fromJson(Map<String, dynamic> json) {
    return ChatPeer(
      id: PeerId(json['id'] as String),
      name: json['name'] as String,
      connectedAt: DateTime.fromMillisecondsSinceEpoch(
        json['connectedAt'] as int,
      ),
      status: ChatPeerStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ChatPeerStatus.connected,
      ),
      isOnline: json['isOnline'] as bool? ?? true,
      lastSeen: json['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastSeen'] as int)
          : null,
      knownBlocks:
          (json['knownBlocks'] as List<dynamic>?)
              ?.map((cidString) => CID.parse(cidString as String))
              .toSet() ??
          <CID>{},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatPeer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ChatPeer(id: $id, name: $name, status: $status, '
        'isOnline: $isOnline, knownBlocks: ${knownBlocks.length})';
  }
}

/// The connection status of a chat peer.
enum ChatPeerStatus {
  discovered,
  connecting,
  connected,
  disconnected,
  failed,
  syncing,
}

/// Extension methods for ChatPeerStatus.
extension ChatPeerStatusExtension on ChatPeerStatus {
  /// Gets a user-friendly display name for the status.
  String get displayName {
    switch (this) {
      case ChatPeerStatus.discovered:
        return 'Discovered';
      case ChatPeerStatus.connecting:
        return 'Connecting';
      case ChatPeerStatus.connected:
        return 'Connected';
      case ChatPeerStatus.disconnected:
        return 'Disconnected';
      case ChatPeerStatus.failed:
        return 'Connection Failed';
      case ChatPeerStatus.syncing:
        return 'Synchronizing';
    }
  }

  /// Whether this status indicates the peer is available for communication.
  bool get isAvailable {
    return this == ChatPeerStatus.discovered ||
        this == ChatPeerStatus.connecting ||
        this == ChatPeerStatus.connected ||
        this == ChatPeerStatus.syncing;
  }
}
