import 'dart:async';
import 'dart:isolate';
import '../data/local/db.dart';
import '../data/local/event_log_repo.dart';
import '../data/local/outbox_repo.dart';
import '../data/local/sync_cursor_repo.dart';
import '../data/remote/api_client.dart';
import '../services/logging_service.dart';
import '../services/metrics_service.dart';
import '../config/feature_flags.dart';
import 'backoff_calculator.dart';

/// Background sync worker using Timer-based approach
class SyncWorker {
  static const String _component = 'SyncWorker';

  static AppDatabase? _database;
  static EventLogRepo? _eventLogRepo;
  static OutboxRepo? _outboxRepo;
  static SyncCursorRepo? _syncCursorRepo;
  static ApiClient? _apiClient;
  static Timer? _periodicTimer;

  /// Initialize the sync worker
  static Future<void> initialize({ApiClient? apiClient}) async {
    try {
      // Initialize database and repositories
      _database = AppDatabase();
      _eventLogRepo = EventLogRepo(_database!);
      _outboxRepo = OutboxRepo(_database!);
      _syncCursorRepo = SyncCursorRepo(_database!);

      // Initialize API client
      _apiClient = apiClient;

      // Schedule periodic sync using Timer
      _schedulePeriodicSync();

      logger.info(
        'Sync worker initialized',
        _component,
        {
          'sync_interval_ms': FeatureFlags.syncInterval.inMilliseconds,
          'max_backoff_ms': FeatureFlags.maxRetryBackoff.inMilliseconds,
        },
      );

    } catch (e) {
      logger.error(
        'Failed to initialize sync worker',
        _component,
        {'error': e.toString()},
      );
    }
  }

  /// Schedule periodic sync using Timer
  static void _schedulePeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(FeatureFlags.syncInterval, (timer) {
      performSync();
    });

    logger.info(
      'Periodic sync scheduled',
      _component,
      {
        'frequency_ms': FeatureFlags.syncInterval.inMilliseconds,
      },
    );
  }

  /// Trigger immediate sync
  static Future<void> syncNow() async {
    try {
      logger.info('Manual sync triggered', _component, {});
      await performSync();
    } catch (e) {
      logger.error(
        'Failed to trigger manual sync',
        _component,
        {'error': e.toString()},
      );
    }
  }

  /// Cancel all sync tasks
  static Future<void> cancelSync() async {
    try {
      _periodicTimer?.cancel();
      _periodicTimer = null;
      logger.info('Sync tasks cancelled', _component, {});
    } catch (e) {
      logger.error(
        'Failed to cancel sync tasks',
        _component,
        {'error': e.toString()},
      );
    }
  }

  /// Perform sync operation
  static Future<bool> performSync() async {
    if (_outboxRepo == null || _eventLogRepo == null || _apiClient == null) {
      logger.error('Sync worker not initialized', _component, {});
      return false;
    }

    try {
      metrics.increment(MetricsService.syncAttempt);
      logger.info('Starting sync operation', _component, {});

      // Get items ready for sync
      final items = await _outboxRepo!.dequeueBatch(limit: 10);
      
      if (items.isEmpty) {
        logger.debug('No items to sync', _component, {});
        return true;
      }

      metrics.increment(MetricsService.outboxDequeued, by: items.length);
      logger.info(
        'Processing sync batch',
        _component,
        {'item_count': items.length},
      );

      int successCount = 0;
      int failureCount = 0;

      for (final item in items) {
        final success = await _syncItem(item);
        if (success) {
          successCount++;
        } else {
          failureCount++;
        }
      }

      // Update sync cursor
      await _syncCursorRepo!.setLastSynced('last_sync', DateTime.now());

      metrics.increment(MetricsService.syncBatchProcessed);
      if (failureCount == 0) {
        metrics.increment(MetricsService.syncSuccess);
      } else {
        metrics.increment(MetricsService.syncFailure);
      }

      logger.info(
        'Sync batch completed',
        _component,
        {
          'success_count': successCount,
          'failure_count': failureCount,
          'total_items': items.length,
        },
      );

      return failureCount == 0;

    } catch (e) {
      logger.error(
        'Sync operation failed',
        _component,
        {'error': e.toString()},
      );
      return false;
    }
  }

  /// Sync individual item
  static Future<bool> _syncItem(OutboxItem item) async {
    try {
      logger.debug(
        'Syncing item',
        _component,
        {
          'item_id': item.id,
          'event_id': item.eventId,
          'endpoint': item.endpoint,
          'method': item.method,
          'attempts': item.attempts,
        },
      );

      // Check if we should retry based on backoff
      if (!BackoffCalculator.shouldRetry(item.nextAttemptAt)) {
        logger.debug(
          'Item not ready for retry',
          _component,
          {
            'item_id': item.id,
            'next_attempt_at': item.nextAttemptAt.toIso8601String(),
          },
        );
        return false;
      }

      // Call appropriate API endpoint based on item endpoint
      ApiResponse response;
      
      if (item.endpoint.contains('attendance')) {
        // Parse attendance event payload
        final payload = item.payload;
        response = await _apiClient!.postAttendance(
          eventId: item.eventId,
          eventType: payload['type'] as String,
          dedupeKey: item.dedupeKey,
          timestamp: DateTime.parse(payload['timestamp'] as String),
          latitude: payload['location']['lat'] as double,
          longitude: payload['location']['lng'] as double,
          accuracy: payload['location']['accuracy'] as double,
          biometricOk: payload['biometric_ok'] as bool? ?? false,
          biometricTimestamp: payload['biometric_timestamp'] != null 
              ? DateTime.parse(payload['biometric_timestamp'] as String)
              : null,
        );
      } else if (item.endpoint.contains('heartbeat')) {
        // Parse heartbeat payload
        final payload = item.payload;
        response = await _apiClient!.postHeartbeat(
          eventId: item.eventId,
          dedupeKey: item.dedupeKey,
          timestamp: DateTime.parse(payload['timestamp'] as String),
          latitude: payload['location']['lat'] as double,
          longitude: payload['location']['lng'] as double,
          accuracy: payload['location']['accuracy'] as double,
        );
      } else {
        await _handleSyncFailure(item, 'Unknown endpoint: ${item.endpoint}', isRetryable: false);
        return false;
      }

      // Handle response
      if (response.success) {
        metrics.increment(MetricsService.outboxSyncSuccess);
        await _handleSyncSuccess(item, response);
        return true;
      } else {
        metrics.increment(MetricsService.outboxSyncFailure);
        if (response.isRetryable) {
          metrics.increment(MetricsService.outboxRetry);
        }
        await _handleSyncFailure(item, response.error!, isRetryable: response.isRetryable);
        return false;
      }

    } catch (e) {
      metrics.increment(MetricsService.outboxSyncFailure);
      metrics.increment(MetricsService.outboxRetry);
      await _handleSyncFailure(item, e.toString(), isRetryable: true);
      return false;
    }
  }

  /// Handle successful sync
  static Future<void> _handleSyncSuccess(OutboxItem item, ApiResponse response) async {
    try {
      // Update event status based on server response
      final eventStatus = response.status == 'CONFIRMED' 
          ? EventStatus.confirmed 
          : EventStatus.rejected;
      
      await _eventLogRepo!.markStatus(item.eventId, eventStatus, response.reason);

      // Track metrics
      if (eventStatus == EventStatus.confirmed) {
        metrics.increment(MetricsService.eventConfirmed);
        metrics.decrement(MetricsService.eventPending);
      } else {
        metrics.increment(MetricsService.eventRejected);
        metrics.decrement(MetricsService.eventPending);
      }

      if (response.isDuplicate) {
        metrics.increment(MetricsService.outboxDuplicate);
      }

      // Remove from outbox
      await _outboxRepo!.removeItem(item.id);

      BackoffCalculator.logBackoffReset('sync_success');

      logger.info(
        'Item synced successfully',
        _component,
        {
          'item_id': item.id,
          'event_id': item.eventId,
          'server_status': response.status,
          'server_reason': response.reason,
          'server_event_id': response.serverEventId,
          'duplicate': response.isDuplicate,
          'attempts': item.attempts + 1,
        },
      );

    } catch (e) {
      logger.error(
        'Failed to handle sync success',
        _component,
        {
          'item_id': item.id,
          'error': e.toString(),
        },
      );
    }
  }

  /// Handle sync failure
  static Future<void> _handleSyncFailure(
    OutboxItem item, 
    String error, 
    {required bool isRetryable}
  ) async {
    try {
      final newAttempts = item.attempts + 1;

      if (!isRetryable) {
        // Mark as rejected for non-retryable errors
        await _eventLogRepo!.markStatus(
          item.eventId, 
          EventStatus.rejected, 
          'Sync failed: $error'
        );
        await _outboxRepo!.removeItem(item.id);

        logger.warn(
          'Item marked as rejected (non-retryable)',
          _component,
          {
            'item_id': item.id,
            'event_id': item.eventId,
            'error': error,
            'attempts': newAttempts,
          },
        );
        return;
      }

      // Calculate backoff for retryable errors
      final nextAttempt = BackoffCalculator.calculateNextAttempt(
        attempts: newAttempts,
      );

      // Update outbox item
      await _outboxRepo!.markAttempt(item.id, error: error);
      await _outboxRepo!.scheduleNextAttempt(item.id, nextAttempt);

      BackoffCalculator.logBackoffProgression(
        attempts: newAttempts,
        delay: nextAttempt.difference(DateTime.now()),
        context: 'sync_failure',
        error: error,
      );

      logger.warn(
        'Item sync failed, scheduled for retry',
        _component,
        {
          'item_id': item.id,
          'event_id': item.eventId,
          'error': error,
          'attempts': newAttempts,
          'next_attempt_at': nextAttempt.toIso8601String(),
        },
      );

    } catch (e) {
      logger.error(
        'Failed to handle sync failure',
        _component,
        {
          'item_id': item.id,
          'error': e.toString(),
        },
      );
    }
  }

}

// Note: WorkManager callback dispatcher removed - using Timer-based approach instead
