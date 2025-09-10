# NearbyConnectionsPeerManager Implementation

## Overview

This directory contains a `NearbyConnectionsPeerManager` implementation that uses Google's Nearby Connections API for peer-to-peer networking in the Eventually Chat application. This enables offline-first chat functionality where devices can discover and communicate with each other directly without requiring an internet connection.

## Files

- `nearby_connections_peer_manager.dart` - Main implementation of the PeerManager interface using nearby_connections
- `mock_peer_manager.dart` - Mock implementation for development and testing
- `permissions_service.dart` - Handles permission requests (simplified implementation)

## Features

### NearbyConnectionsPeerManager

The `NearbyConnectionsPeerManager` class implements the `PeerManager` interface from the Eventually library and provides:

- **Peer Discovery**: Automatically discovers nearby devices using advertising and discovery
- **Connection Management**: Handles connection establishment, maintenance, and cleanup
- **Message Exchange**: Enables sending and receiving messages between connected peers
- **Block Synchronization**: Supports requesting and sharing blocks for Merkle DAG sync
- **Statistics**: Provides detailed peer connection statistics

### Key Components

#### 1. Advertising and Discovery
```dart
// Starts advertising this device to be discoverable
await _startAdvertising();

// Starts discovering other nearby devices
await _startDiscovering();
```

#### 2. Connection Management
- Auto-accepts incoming connections
- Maintains connection state
- Handles connection failures and disconnections
- Periodic restarts to find new peers

#### 3. Message Types
The implementation handles various message types for peer communication:
- Block requests
- Block responses  
- Has-block queries
- Ping/pong for latency testing
- Generic messages for chat

#### 4. Peer Lifecycle
1. **Discovered** - Peer found via nearby connections discovery
2. **Connecting** - Attempting to establish connection
3. **Connected** - Successfully connected and ready for communication
4. **Disconnected** - Connection lost or terminated
5. **Failed** - Connection attempt failed

## Configuration

### Service Settings
```dart
static const String _serviceId = 'com.eventually.chat';
static const Strategy _strategy = Strategy.P2P_CLUSTER;
```

- `_serviceId`: Unique identifier for the chat application
- `_strategy`: Connection strategy (P2P_CLUSTER allows multiple connections)

### Timers
- Discovery restart: Every 2 minutes
- Advertising restart: Every 3 minutes
- Connection timeout: 10 seconds

## Usage

### Basic Setup
```dart
// Initialize the peer manager
final peerManager = NearbyConnectionsPeerManager(
  userId: 'unique-user-id',
  userName: 'Display Name',
);

// Start discovery and advertising
await peerManager.startDiscovery();

// Listen for peer events
peerManager.peerEvents.listen((event) {
  switch (event) {
    case PeerDiscovered():
      print('Discovered peer: ${event.peer.id}');
      break;
    case PeerConnected():
      print('Connected to peer: ${event.peer.id}');
      break;
    case PeerDisconnected():
      print('Disconnected from peer: ${event.peer.id}');
      break;
  }
});
```

### Integration with Eventually Chat Service
The peer manager is integrated into the main chat service:

```dart
// Initialize peer manager
_peerManager = NearbyConnectionsPeerManager(
  userId: _userId!,
  userName: _userName!,
);

// Initialize synchronizer with peer manager
_synchronizer = DefaultSynchronizer(
  store: _store,
  dag: _dag,
  peerManager: _peerManager,
);
```

## Dependencies

### Required Package
```yaml
dependencies:
  nearby_connections: ^4.3.0
```

### Android Permissions
Add these permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Required for Nearby Connections -->
<uses-permission android:maxSdkVersion="31" android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:maxSdkVersion="31" android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:maxSdkVersion="30" android:name="android.permission.BLUETOOTH" />
<uses-permission android:maxSdkVersion="30" android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:maxSdkVersion="28" android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:minSdkVersion="29" android:maxSdkVersion="31" android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:minSdkVersion="31" android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:minSdkVersion="31" android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:minSdkVersion="31" android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:minSdkVersion="32" android:name="android.permission.NEARBY_WIFI_DEVICES" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

## Platform Support

- **Android**: Full support via Google's Nearby Connections API
- **iOS**: Not supported (nearby_connections is Android-only)

For iOS support, you would need to implement a similar peer manager using:
- MultipeerConnectivity framework
- Apple's Nearby Interaction framework
- Or a cross-platform alternative like flutter_nearby_connections

## Limitations and TODOs

### Current Limitations
1. **Android Only**: The nearby_connections package only supports Android
2. **Simplified Message Protocol**: Uses basic JSON messages instead of structured protocol
3. **No Request/Response Matching**: Block requests don't wait for actual responses
4. **Basic Error Handling**: Limited retry logic and error recovery
5. **Security**: No authentication or encryption (relies on Nearby Connections security)

### Future Improvements
1. **Enhanced Message Protocol**: Implement proper request/response correlation
2. **Better Error Handling**: Add retry logic, connection recovery, and graceful degradation
3. **Security Layer**: Add message signing and optional encryption
4. **iOS Support**: Implement MultipeerConnectivity version
5. **Performance Optimization**: Implement message queuing and flow control
6. **Network Quality**: Add connection quality assessment and peer prioritization

## Testing

### Mock Implementation
For development and testing, use `MockPeerManager` which simulates peer connections:

```dart
// Use mock peer manager for testing
final peerManager = MockPeerManager(userId: 'test-user');
```

### Testing on Real Devices
1. Build the app on multiple Android devices
2. Enable location services on all devices
3. Grant all required permissions
4. Start the app on each device
5. Observe automatic peer discovery and connection

## Troubleshooting

### Common Issues
1. **Location Services**: Must be enabled for nearby connections to work
2. **Permissions**: All Bluetooth and location permissions must be granted
3. **Device Compatibility**: Some older Android devices may have limited support
4. **Network Environment**: WiFi and Bluetooth should be enabled for best performance

### Debug Logging
The implementation includes extensive debug logging:
- Peer discovery events
- Connection state changes  
- Message transmission
- Error conditions

Look for log messages prefixed with:
- 🔍 (Discovery)
- 🤝 (Connection)
- 📤 (Outgoing messages)
- 📥 (Incoming messages)
- ❌ (Errors)
- ✅ (Success)

## Related Documentation

- [Google Nearby Connections API](https://developers.google.com/nearby/connections/overview)
- [nearby_connections Flutter package](https://pub.dev/packages/nearby_connections)
- [Eventually Library Documentation](../../packages/eventually/README.md)