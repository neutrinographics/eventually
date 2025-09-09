# Eventually Chat

A Flutter chat application demonstrating the capabilities of the Eventually library for Merkle DAG synchronization and distributed content-addressed storage.

## ✨ Features

- **🔗 Content-Addressed Storage** - Messages stored as blocks with unique Content Identifiers (CIDs)
- **🌳 Merkle DAG Structure** - Messages form a Directed Acyclic Graph for data integrity
- **🔄 Automatic Synchronization** - Peer-to-peer sync of chat history using Eventually library
- **👥 Distributed Networking** - Decentralized chat without central servers
- **📊 DAG Visualization** - Real-time statistics about the Merkle DAG structure
- **⚡ Eventual Consistency** - Messages eventually reach all connected peers
- **🔐 Content Integrity** - Cryptographic verification of message blocks
- **💾 Persistent Storage** - Messages stored locally using Hive database

## 📚 What is Eventually?

The Eventually library provides Merkle DAG synchronization with IPFS-like protocols for distributed content-addressed storage. Key concepts:

- **Content Identifiers (CIDs)**: Unique identifiers computed from content hash
- **Blocks**: Units of data storage identified by their CIDs
- **Merkle DAG**: Directed Acyclic Graph structure for linking related data
- **Synchronization**: Automatic exchange of missing blocks between peers
- **Store Interface**: Pluggable storage backends for persistence

## 🏗️ Architecture

### Data Flow
```
Message Creation → Block Generation → DAG Storage → Peer Synchronization
     ↓                   ↓              ↓              ↓
  JSON Encode      →   CID Hash   →  Local Store →  Network Sync
```

### Key Components

1. **EventuallyChatService**: Main service coordinating all chat functionality
2. **ChatMessage**: Message model that creates content-addressed blocks
3. **HiveDAGStore**: Persistent storage implementation using Hive
4. **MockPeerManager**: Simulated peer-to-peer networking (demo only)
5. **DAG Synchronizer**: Handles block exchange between peers

### Storage Architecture

- **Blocks**: Raw message data stored as content-addressed blocks
- **DAG**: In-memory graph structure linking related blocks
- **Hive Store**: Persistent storage with metadata indexing
- **CID Addressing**: Each message has a unique content identifier

## 📱 Requirements

- **Flutter SDK** (>=3.16.0)
- **Dart SDK** (>=3.9.0)
- **Android device** (for permissions demo)
- **Storage permissions** for local data persistence

## 🚀 Getting Started

### Installation

1. **Navigate to the project directory:**
```bash
cd eventually/apps/eventually_chat
```

2. **Install dependencies:**
```bash
flutter pub get
```

3. **Run the app:**
```bash
flutter run
```

### First Launch

1. **Enter your display name** when prompted
2. **Grant storage permissions** if requested
3. **Start sending messages** to create blocks in the DAG
4. **View DAG statistics** by tapping the tree icon
5. **Check peer connections** via the people icon

## 💬 How It Works

### Message Storage
```dart
// 1. Create message with content
final message = ChatMessage.create(
  senderId: userId,
  senderName: userName,
  content: "Hello, DAG!",
);

// 2. Message becomes a content-addressed block
final block = message.block;  // Has unique CID
final cid = message.cid;      // Content identifier

// 3. Block stored in DAG and synchronized
await store.put(block);
dag.addBlock(block);
```

### Peer Synchronization
```dart
// 1. Announce new blocks to peers
await synchronizer.announceBlocks({messageCid});

// 2. Peers request missing blocks
final missingBlocks = await synchronizer.fetchMissingBlocks(rootCid);

// 3. Automatic sync ensures eventual consistency
synchronizer.startContinuousSync();
```

### Content Addressing
- Each message gets a unique CID based on its content
- Identical messages have identical CIDs (deduplication)
- CIDs are cryptographically verifiable
- Content cannot be tampered without changing the CID

## 🔧 Technical Details

### Message Format
```json
{
  "id": "uuid-v4",
  "senderId": "user-uuid",
  "senderName": "Display Name",
  "content": "Message text",
  "timestamp": 1640995200000,
  "type": "chat_message"
}
```

### Block Structure
- **Data**: JSON-encoded message
- **CID**: Content identifier (version 1)
- **Codec**: DAG-JSON for structured data
- **Hash**: SHA-256 cryptographic hash

### DAG Properties
- **Blocks**: Total number of message blocks
- **Size**: Total storage size in bytes
- **Depth**: Maximum depth of the DAG
- **Roots**: Entry points (typically user presence)
- **Leaves**: Terminal nodes (latest messages)

## 📊 DAG Statistics

The app provides real-time statistics about the Merkle DAG:

- **Total Blocks**: Number of content-addressed blocks
- **Storage Size**: Total bytes used by all blocks
- **DAG Depth**: Maximum chain length in the graph
- **Sync Status**: Peer synchronization success rate
- **Network Health**: Connected peers and sync statistics

## 🎯 Demo Features

Since this is a demonstration app, it includes:

- **Mock Peer Manager**: Simulates peer-to-peer connections
- **Virtual Peers**: Randomly generated peers with realistic names
- **Simulated Network**: Peer discovery and disconnection events
- **Local Storage**: All data persisted using Hive database

## 🔄 Real-World Usage

In a production environment, replace the mock components with:

- **Real Networking**: TCP, WebRTC, or libp2p transport
- **Peer Discovery**: mDNS, DHT, or rendezvous servers
- **Authentication**: Cryptographic peer identity verification
- **NAT Traversal**: STUN/TURN servers for connectivity
- **Conflict Resolution**: Operational transforms or CRDTs

## 🛠️ Development

### Project Structure
```
lib/
├── models/
│   ├── chat_message.dart      # Content-addressed message model
│   └── chat_peer.dart         # Peer connection management
├── screens/
│   ├── name_input_screen.dart # User onboarding
│   └── chat_screen.dart       # Main chat interface
├── services/
│   ├── eventually_chat_service.dart  # Main service coordinator
│   ├── hive_dag_store.dart           # Persistent block storage
│   ├── mock_peer_manager.dart        # Simulated networking
│   └── permissions_service.dart      # Android permissions
├── widgets/
│   ├── message_bubble.dart           # Chat message UI
│   ├── peer_list_drawer.dart         # Peer connection list
│   └── dag_stats_banner.dart         # DAG statistics display
└── main.dart                         # App entry point
```

### Key Dependencies
- **eventually**: Merkle DAG synchronization library
- **hive**: Local database for block storage
- **provider**: State management
- **uuid**: Unique identifier generation

### Testing
```bash
# Run unit tests
flutter test

# Run integration tests
flutter test integration_test/
```

## 🔍 Debugging

### DAG Statistics
Access detailed DAG information through:
- Tap the tree icon in the chat screen
- View block count, storage size, and depth
- Monitor peer connections and sync status

### Logs
The app provides detailed logging:
```
✅ EventuallyChatService initialized
📤 Sent message: Hello, world!
🔄 Sync started with peer: alice-uuid
📥 Fetched 5 blocks from peer: bob-uuid
```

### Storage Inspection
Blocks are stored in Hive boxes:
- `eventually_blocks`: Raw block data
- `eventually_metadata`: Block metadata and indexing

## 🚀 Future Enhancements

### Planned Features
- **Real P2P Networking**: Replace mock with actual network protocols
- **File Sharing**: Support for media and document blocks
- **Encryption**: End-to-end encryption for message blocks
- **Conflict Resolution**: Handle concurrent message creation
- **Mobile Optimization**: Battery and bandwidth optimizations

### Integration Ideas
- **IPFS Compatibility**: Use IPFS for public content distribution
- **Blockchain Bridge**: Anchor DAG state to blockchain
- **Federated Chat**: Bridge with existing chat protocols
- **IoT Integration**: Sensor data as content-addressed blocks

## 📄 License

This project demonstrates the Eventually library capabilities. See the main repository for licensing information.

## 🤝 Contributing

This is a demonstration app for the Eventually library. For contributions:
1. Focus on Eventually library integration examples
2. Improve DAG visualization and statistics
3. Add real-world networking implementations
4. Enhance message types and block structures

## 🎉 Success! You now have a working Merkle DAG chat app!

**Quick Start:** Enter your name → Send messages → Watch DAG grow! 🌳

**Explore:** Tap the tree icon for DAG stats, people icon for peer connections.

---

*This app demonstrates distributed systems concepts using content-addressed storage and Merkle DAGs. Perfect for learning about decentralized applications and peer-to-peer networking!*