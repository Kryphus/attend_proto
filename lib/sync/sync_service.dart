import 'dart:async';
import '../services/logging_service.dart';
import '../data/local/sync_cursor_repo.dart';
import '../data/remote/api_client.dart';
import 'sync_worker.dart';
import 'connectivity_service.dart';

/// Main sync service that coordinates background sync and connectivity
class SyncService {
  static const String _component = 'SyncService';
  
  final ConnectivityService _connectivityService;
  final SyncCursorRepo _syncCursorRepo;
  final ApiClient? _apiClient;
  
  StreamSubscription<void>? _reconnectionSubscription;
  bool _isInitialized = false;

  SyncService({
    required ConnectivityService connectivityService,
    required SyncCursorRepo syncCursorRepo,
    ApiClient? apiClient,
  }) : _connectivityService = connectivityService,
       _syncCursorRepo = syncCursorRepo,
       _apiClient = apiClient;

  /// Initialize the sync service
  Future<void> initialize() async {
    if (_isInitialized) {
      logger.warn('Sync service already initialized', _component, {});
      return;
    }

    try {
      // Initialize connectivity monitoring
      await _connectivityService.initialize();

      // Initialize sync worker
      await SyncWorker.initialize(apiClient: _apiClient);

      // Listen for reconnection events
      _reconnectionSubscription = _connectivityService.reconnectionStream.listen(
        (_) => _onConnectivityRegained(),
        onError: (error) {
          logger.error(
            'Reconnection stream error',
            _component,
            {'error': error.toString()},
          );
        },
      );

      _isInitialized = true;

      logger.info(
        'Sync service initialized',
        _component,
        {
          'connectivity_status': _connectivityService.isConnected,
        },
      );

    } catch (e) {
      logger.error(
        'Failed to initialize sync service',
        _component,
        {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Handle connectivity regained
  void _onConnectivityRegained() {
    logger.info(
      'Connectivity regained, triggering sync',
      _component,
      {},
    );
    
    // Trigger immediate sync when connectivity is regained
    syncNow();
  }

  /// Trigger manual sync
  Future<void> syncNow() async {
    try {
      logger.info('Manual sync requested', _component, {});

      // Check connectivity first
      final isConnected = await _connectivityService.checkConnectivity();
      if (!isConnected) {
        logger.warn(
          'Sync requested but no connectivity',
          _component,
          {'connectivity_status': false},
        );
        return;
      }

      // Trigger sync worker
      await SyncWorker.syncNow();

      logger.info(
        'Manual sync triggered successfully',
        _component,
        {},
      );

    } catch (e) {
      logger.error(
        'Failed to trigger manual sync',
        _component,
        {'error': e.toString()},
      );
    }
  }

  /// Get sync status information
  Future<SyncStatus> getSyncStatus() async {
    try {
      final lastSynced = await _syncCursorRepo.getLastSynced('last_sync');
      final isConnected = _connectivityService.isConnected;
      
      return SyncStatus(
        isConnected: isConnected,
        lastSyncTime: lastSynced,
        connectivityDescription: _connectivityService.getConnectivityDescription(),
      );

    } catch (e) {
      logger.error(
        'Failed to get sync status',
        _component,
        {'error': e.toString()},
      );
      
      return SyncStatus(
        isConnected: false,
        lastSyncTime: null,
        connectivityDescription: 'Unknown',
      );
    }
  }

  /// Get connectivity stream for UI updates
  Stream<bool> get connectivityStream => _connectivityService.connectivityStream;

  /// Check if sync service is ready
  bool get isInitialized => _isInitialized;

  /// Dispose of resources
  void dispose() {
    _reconnectionSubscription?.cancel();
    _connectivityService.dispose();
    
    logger.info('Sync service disposed', _component, {});
  }
}

/// Sync status information
class SyncStatus {
  final bool isConnected;
  final DateTime? lastSyncTime;
  final String connectivityDescription;

  SyncStatus({
    required this.isConnected,
    required this.lastSyncTime,
    required this.connectivityDescription,
  });

  /// Get formatted last sync time
  String get lastSyncFormatted {
    if (lastSyncTime == null) {
      return 'Never';
    }
    
    final now = DateTime.now();
    final difference = now.difference(lastSyncTime!);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  /// Get sync status description for UI
  String get statusDescription {
    if (!isConnected) {
      return 'Offline - sync paused';
    }
    
    if (lastSyncTime == null) {
      return 'Online - ready to sync';
    }
    
    return 'Online - last sync $lastSyncFormatted';
  }

  @override
  String toString() {
    return 'SyncStatus(connected: $isConnected, lastSync: $lastSyncFormatted, description: $connectivityDescription)';
  }
}
