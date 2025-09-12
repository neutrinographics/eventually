import 'package:eventually/src/peer.dart';
import 'package:meta/meta.dart';

/// Configuration for peer manager behavior.
///
/// This class contains all configurable parameters that control how
/// peer discovery, connection management, and synchronization operates.
/// All configurations are validated at creation time and are immutable.
@immutable
class PeerConfig {
  /// Unique identifier for this node in the peer network.
  final PeerId nodeId;

  /// Display name for this node during peer discovery.
  final String? displayName;

  /// Interval between synchronization attempts.
  ///
  /// This determines how frequently this node will synchronize its state
  /// with its peers. Shorter intervals provide faster synchronization but
  /// higher resource usage.
  final Duration syncInterval;

  /// Interval between peer discovery attempts.
  ///
  /// This determines how frequently this node will scan for new peers.
  /// Shorter intervals provide faster peer discovery but higher resource usage.
  final Duration discoveryInterval;

  /// Maximum time to wait for a connection operation to complete.
  ///
  /// If a connection attempt takes longer than this timeout,
  /// the operation will be cancelled and potentially retried.
  final Duration connectionTimeout;

  /// Maximum time to wait for a handshake operation to complete.
  ///
  /// After transport connection is established, this timeout applies
  /// to the peer identity discovery handshake process.
  final Duration handshakeTimeout;

  /// Whether to automatically connect to discovered peers.
  ///
  /// When enabled, the peer manager will automatically attempt to
  /// establish connections with newly discovered transport peers.
  final bool autoConnect;

  /// Maximum number of concurrent peer connections.
  ///
  /// This prevents resource exhaustion and helps control network overhead.
  /// Once this limit is reached, new connections may be rejected.
  final int maxConnections;

  /// Strategy for selecting which peers to connect to.
  final PeerSelectionStrategy selectionStrategy;

  /// Whether to enable connection health checking.
  ///
  /// When enabled, the peer manager will periodically check
  /// the health of existing connections and reconnect if necessary.
  final bool enableHealthCheck;

  /// Interval for connection health checks (if enabled).
  final Duration healthCheckInterval;

  /// Maximum time to wait for a peer to respond to health checks.
  final Duration healthCheckTimeout;

  /// Whether to enable automatic reconnection on connection loss.
  ///
  /// When enabled, the peer manager will attempt to reconnect
  /// to peers when connections are lost unexpectedly.
  final bool enableAutoReconnect;

  /// Delay before attempting to reconnect after connection loss.
  final Duration reconnectDelay;

  /// Maximum number of reconnection attempts before giving up.
  final int maxReconnectAttempts;

  /// Whether to enable peer metadata exchange.
  ///
  /// When enabled, peers will exchange metadata during handshake
  /// which can be used for application-specific peer selection.
  final bool enableMetadataExchange;

  /// Additional transport-specific configuration.
  final Map<String, dynamic> transportConfig;

  /// Creates a new peer configuration with the specified parameters.
  ///
  /// All required parameters must be provided. Optional parameters have
  /// sensible defaults. Configuration is validated at creation time.
  const PeerConfig({
    required this.nodeId,
    this.displayName,
    this.syncInterval = const Duration(seconds: 5),
    this.discoveryInterval = const Duration(seconds: 30),
    this.connectionTimeout = const Duration(seconds: 10),
    this.handshakeTimeout = const Duration(seconds: 5),
    this.autoConnect = true,
    this.maxConnections = 10,
    this.selectionStrategy = PeerSelectionStrategy.firstAvailable,
    this.enableHealthCheck = true,
    this.healthCheckInterval = const Duration(minutes: 1),
    this.healthCheckTimeout = const Duration(seconds: 5),
    this.enableAutoReconnect = true,
    this.reconnectDelay = const Duration(seconds: 5),
    this.maxReconnectAttempts = 3,
    this.enableMetadataExchange = true,
    this.transportConfig = const {},
  }) : assert(
         discoveryInterval > Duration.zero,
         'Discovery interval must be positive',
       ),
       assert(
         connectionTimeout > Duration.zero,
         'Connection timeout must be positive',
       ),
       assert(
         handshakeTimeout > Duration.zero,
         'Handshake timeout must be positive',
       ),
       assert(maxConnections > 0, 'Max connections must be positive'),
       assert(
         healthCheckInterval > Duration.zero,
         'Health check interval must be positive',
       ),
       assert(
         healthCheckTimeout > Duration.zero,
         'Health check timeout must be positive',
       ),
       assert(
         reconnectDelay >= Duration.zero,
         'Reconnect delay must be non-negative',
       ),
       assert(
         maxReconnectAttempts >= 0,
         'Max reconnect attempts must be non-negative',
       );

  /// Creates a configuration optimized for nearby connections.
  ///
  /// This configuration uses settings optimized for local peer-to-peer
  /// connections with fast discovery and connection establishment.
  factory PeerConfig.nearby({
    required PeerId nodeId,
    String? displayName,
    Duration? discoveryInterval,
    bool? autoConnect,
    int? maxConnections,
  }) {
    return PeerConfig(
      nodeId: nodeId,
      displayName: displayName ?? nodeId.value,
      discoveryInterval: discoveryInterval ?? const Duration(seconds: 10),
      connectionTimeout: const Duration(seconds: 8),
      handshakeTimeout: const Duration(seconds: 3),
      autoConnect: autoConnect ?? true,
      maxConnections: maxConnections ?? 5,
      selectionStrategy: PeerSelectionStrategy.firstAvailable,
      enableHealthCheck: true,
      healthCheckInterval: const Duration(seconds: 30),
      enableAutoReconnect: true,
      reconnectDelay: const Duration(seconds: 2),
      maxReconnectAttempts: 5,
    );
  }

  /// Creates a configuration optimized for low-latency scenarios.
  ///
  /// This configuration uses aggressive settings for fastest possible
  /// peer discovery and connection establishment.
  factory PeerConfig.lowLatency({
    required PeerId nodeId,
    String? displayName,
    int? maxConnections,
  }) {
    return PeerConfig(
      nodeId: nodeId,
      displayName: displayName ?? nodeId.value,
      discoveryInterval: const Duration(seconds: 5),
      connectionTimeout: const Duration(seconds: 5),
      handshakeTimeout: const Duration(seconds: 2),
      autoConnect: true,
      maxConnections: maxConnections ?? 8,
      selectionStrategy: PeerSelectionStrategy.mostReliable,
      enableHealthCheck: true,
      healthCheckInterval: const Duration(seconds: 15),
      healthCheckTimeout: const Duration(seconds: 3),
      enableAutoReconnect: true,
      reconnectDelay: const Duration(seconds: 1),
      maxReconnectAttempts: 10,
    );
  }

  /// Creates a configuration optimized for low-resource scenarios.
  ///
  /// This configuration uses conservative settings to minimize resource
  /// usage at the cost of slower discovery and connection establishment.
  factory PeerConfig.lowResource({
    required PeerId nodeId,
    String? displayName,
    Duration? discoveryInterval,
    int? maxConnections,
  }) {
    return PeerConfig(
      nodeId: nodeId,
      displayName: displayName,
      discoveryInterval: discoveryInterval ?? const Duration(minutes: 2),
      connectionTimeout: const Duration(seconds: 30),
      handshakeTimeout: const Duration(seconds: 10),
      autoConnect: false,
      maxConnections: maxConnections ?? 3,
      selectionStrategy: PeerSelectionStrategy.leastConnections,
      enableHealthCheck: false,
      enableAutoReconnect: false,
      maxReconnectAttempts: 1,
    );
  }

  /// Creates a configuration optimized for reliability.
  ///
  /// This configuration prioritizes connection stability and fault tolerance
  /// over speed or resource efficiency.
  factory PeerConfig.reliable({
    required PeerId nodeId,
    String? displayName,
    int? maxConnections,
  }) {
    return PeerConfig(
      nodeId: nodeId,
      displayName: displayName ?? nodeId.value,
      discoveryInterval: const Duration(seconds: 20),
      connectionTimeout: const Duration(seconds: 15),
      handshakeTimeout: const Duration(seconds: 8),
      autoConnect: true,
      maxConnections: maxConnections ?? 6,
      selectionStrategy: PeerSelectionStrategy.mostReliable,
      enableHealthCheck: true,
      healthCheckInterval: const Duration(seconds: 45),
      healthCheckTimeout: const Duration(seconds: 8),
      enableAutoReconnect: true,
      reconnectDelay: const Duration(seconds: 10),
      maxReconnectAttempts: 8,
    );
  }

  /// Creates a copy of this configuration with optionally modified values.
  PeerConfig copyWith({
    PeerId? nodeId,
    String? displayName,
    Duration? discoveryInterval,
    Duration? connectionTimeout,
    Duration? handshakeTimeout,
    bool? autoConnect,
    int? maxConnections,
    PeerSelectionStrategy? selectionStrategy,
    bool? enableHealthCheck,
    Duration? healthCheckInterval,
    Duration? healthCheckTimeout,
    bool? enableAutoReconnect,
    Duration? reconnectDelay,
    int? maxReconnectAttempts,
    bool? enableMetadataExchange,
    Map<String, dynamic>? transportConfig,
  }) {
    return PeerConfig(
      nodeId: nodeId ?? this.nodeId,
      displayName: displayName ?? this.displayName,
      discoveryInterval: discoveryInterval ?? this.discoveryInterval,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      handshakeTimeout: handshakeTimeout ?? this.handshakeTimeout,
      autoConnect: autoConnect ?? this.autoConnect,
      maxConnections: maxConnections ?? this.maxConnections,
      selectionStrategy: selectionStrategy ?? this.selectionStrategy,
      enableHealthCheck: enableHealthCheck ?? this.enableHealthCheck,
      healthCheckInterval: healthCheckInterval ?? this.healthCheckInterval,
      healthCheckTimeout: healthCheckTimeout ?? this.healthCheckTimeout,
      enableAutoReconnect: enableAutoReconnect ?? this.enableAutoReconnect,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      enableMetadataExchange:
          enableMetadataExchange ?? this.enableMetadataExchange,
      transportConfig: transportConfig ?? this.transportConfig,
    );
  }

  /// Gets the effective display name for this peer.
  String get effectiveDisplayName => displayName ?? nodeId.value;

  @override
  String toString() {
    return 'PeerConfig('
        'nodeId: $nodeId, '
        'displayName: $displayName, '
        'discoveryInterval: $discoveryInterval, '
        'connectionTimeout: $connectionTimeout, '
        'handshakeTimeout: $handshakeTimeout, '
        'autoConnect: $autoConnect, '
        'maxConnections: $maxConnections, '
        'selectionStrategy: $selectionStrategy, '
        'enableHealthCheck: $enableHealthCheck, '
        'healthCheckInterval: $healthCheckInterval, '
        'healthCheckTimeout: $healthCheckTimeout, '
        'enableAutoReconnect: $enableAutoReconnect, '
        'reconnectDelay: $reconnectDelay, '
        'maxReconnectAttempts: $maxReconnectAttempts, '
        'enableMetadataExchange: $enableMetadataExchange'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PeerConfig) return false;

    return nodeId == other.nodeId &&
        displayName == other.displayName &&
        discoveryInterval == other.discoveryInterval &&
        connectionTimeout == other.connectionTimeout &&
        handshakeTimeout == other.handshakeTimeout &&
        autoConnect == other.autoConnect &&
        maxConnections == other.maxConnections &&
        selectionStrategy == other.selectionStrategy &&
        enableHealthCheck == other.enableHealthCheck &&
        healthCheckInterval == other.healthCheckInterval &&
        healthCheckTimeout == other.healthCheckTimeout &&
        enableAutoReconnect == other.enableAutoReconnect &&
        reconnectDelay == other.reconnectDelay &&
        maxReconnectAttempts == other.maxReconnectAttempts &&
        enableMetadataExchange == other.enableMetadataExchange &&
        transportConfig == other.transportConfig;
  }

  @override
  int get hashCode {
    return Object.hash(
      nodeId,
      displayName,
      discoveryInterval,
      connectionTimeout,
      handshakeTimeout,
      autoConnect,
      maxConnections,
      selectionStrategy,
      enableHealthCheck,
      healthCheckInterval,
      healthCheckTimeout,
      enableAutoReconnect,
      reconnectDelay,
      maxReconnectAttempts,
      enableMetadataExchange,
      Object.hashAll(transportConfig.entries),
    );
  }
}

/// Strategy for selecting which peers to connect to.
enum PeerSelectionStrategy {
  /// Connect to the first available peer discovered.
  ///
  /// This is the fastest strategy and works well when any peer is suitable.
  firstAvailable,

  /// Randomly select from available peers.
  ///
  /// This provides good load distribution across the network
  /// and is suitable for most general use cases.
  random,

  /// Select peers with the least number of existing connections.
  ///
  /// This strategy helps balance connection load across peers
  /// and is useful in scenarios where peer capacity matters.
  leastConnections,

  /// Select peers based on their reliability and response time.
  ///
  /// Prioritizes peers that have been responsive and reliable
  /// in past connections. Requires connection history tracking.
  mostReliable,

  /// Select peers with the shortest estimated latency.
  ///
  /// Prioritizes peers that are closest in network terms.
  /// Requires latency measurement capabilities.
  lowestLatency,

  /// Round-robin selection of available peers.
  ///
  /// Cycles through all known peers in order, ensuring
  /// each peer has an equal chance of being selected.
  roundRobin,
}

/// Exception thrown when peer configuration is invalid.
class InvalidPeerConfigException implements Exception {
  const InvalidPeerConfigException(this.message);

  final String message;

  @override
  String toString() => 'InvalidPeerConfigException: $message';
}
