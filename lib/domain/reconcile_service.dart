import '../data/local/event_log_repo.dart';
import '../data/local/sync_cursor_repo.dart';
import '../data/remote/api_client.dart';
import '../services/logging_service.dart';
import '../services/metrics_service.dart';

/// Service for reconciling local event statuses with authoritative server state
/// 
/// The ReconcileService periodically fetches recent events from the server
/// and updates local event statuses to match the server's authoritative decisions.
/// This ensures that any server-side rejections or status changes are reflected locally.
class ReconcileService {
  static const String _component = 'ReconcileService';
  static const String _cursorKey = 'last_reconcile_at';

  final EventLogRepo _eventLogRepo;
  final SyncCursorRepo _syncCursorRepo;
  final ApiClient _apiClient;

  ReconcileService({
    required EventLogRepo eventLogRepo,
    required SyncCursorRepo syncCursorRepo,
    required ApiClient apiClient,
  })  : _eventLogRepo = eventLogRepo,
        _syncCursorRepo = syncCursorRepo,
        _apiClient = apiClient;

  /// Performs reconciliation by fetching recent server events and updating local state
  /// 
  /// Returns [ReconcileResult] with statistics about the reconciliation operation.
  Future<ReconcileResult> reconcile() async {
    final startTime = DateTime.now();
    
    try {
      metrics.increment(MetricsService.reconcileAttempt);
      logger.info(
        'Starting reconciliation',
        _component,
        {'start_time': startTime.toIso8601String()},
      );

      // Get last reconciliation time
      final lastReconcileAt = await _syncCursorRepo.getLastSynced(_cursorKey);
      
      // Fetch recent server events (last 24 hours or since last reconcile)
      final since = lastReconcileAt ?? DateTime.now().subtract(const Duration(hours: 24));
      final serverEvents = await _apiClient.getRecentEvents(since: since, limit: 500);

      if (serverEvents.isEmpty) {
        logger.debug(
          'No server events to reconcile',
          _component,
          {'since': since.toIso8601String()},
        );
        
        // Still update cursor to mark successful reconciliation
        await _syncCursorRepo.setLastSynced(_cursorKey, startTime);
        
        return ReconcileResult(
          eventsChecked: 0,
          eventsUpdated: 0,
          eventsMissing: 0,
          duration: DateTime.now().difference(startTime),
          success: true,
        );
      }

      logger.info(
        'Fetched server events for reconciliation',
        _component,
        {
          'event_count': serverEvents.length,
          'since': since.toIso8601String(),
        },
      );

      int eventsChecked = 0;
      int eventsUpdated = 0;
      int eventsMissing = 0;

      // Process each server event
      for (final serverEvent in serverEvents) {
        eventsChecked++;
        
        final result = await _reconcileEvent(serverEvent);
        
        if (result == ReconcileEventResult.updated) {
          eventsUpdated++;
        } else if (result == ReconcileEventResult.missing) {
          eventsMissing++;
        }
      }

      // Update reconciliation cursor
      await _syncCursorRepo.setLastSynced(_cursorKey, startTime);

      final duration = DateTime.now().difference(startTime);
      
      metrics.increment(MetricsService.reconcileSuccess);
      metrics.increment(MetricsService.reconcileEventsUpdated, by: eventsUpdated);

      logger.info(
        'Reconciliation completed',
        _component,
        {
          'events_checked': eventsChecked,
          'events_updated': eventsUpdated,
          'events_missing': eventsMissing,
          'duration_ms': duration.inMilliseconds,
        },
      );

      return ReconcileResult(
        eventsChecked: eventsChecked,
        eventsUpdated: eventsUpdated,
        eventsMissing: eventsMissing,
        duration: duration,
        success: true,
      );

    } catch (e) {
      metrics.increment(MetricsService.reconcileFailure);
      logger.error(
        'Reconciliation failed',
        _component,
        {'error': e.toString()},
      );

      return ReconcileResult(
        eventsChecked: 0,
        eventsUpdated: 0,
        eventsMissing: 0,
        duration: DateTime.now().difference(startTime),
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Reconciles a single server event with local state
  /// 
  /// Returns [ReconcileEventResult] indicating what action was taken.
  Future<ReconcileEventResult> _reconcileEvent(Map<String, dynamic> serverEvent) async {
    try {
      final clientEventId = serverEvent['client_event_id'] as String?;
      
      if (clientEventId == null) {
        logger.warn(
          'Server event missing client_event_id',
          _component,
          {
            'server_event_id': serverEvent['id'],
            'event_type': serverEvent['event_type'],
          },
        );
        return ReconcileEventResult.skipped;
      }

      // Find local event by client_event_id
      final localEvents = await _eventLogRepo.getEvents();
      final localEvent = localEvents.where((e) => e.id == clientEventId).firstOrNull;

      if (localEvent == null) {
        logger.warn(
          'Local event not found for server event',
          _component,
          {
            'client_event_id': clientEventId,
            'server_event_id': serverEvent['id'],
            'server_status': serverEvent['status'],
          },
        );
        return ReconcileEventResult.missing;
      }

      // Compare statuses
      final serverStatus = serverEvent['status'] as String;
      final localStatus = localEvent.status;

      if (serverStatus == localStatus) {
        // Statuses match - no update needed (idempotent)
        logger.debug(
          'Event status already matches server',
          _component,
          {
            'event_id': clientEventId,
            'status': serverStatus,
          },
        );
        return ReconcileEventResult.unchanged;
      }

      // Server status differs - update local event
      final serverReason = serverEvent['server_reason'] as String?;
      
      final newStatus = _mapServerStatusToLocal(serverStatus);
      await _eventLogRepo.markStatus(clientEventId, newStatus, serverReason);

      logger.info(
        'Event status reconciled with server',
        _component,
        {
          'event_id': clientEventId,
          'old_status': localStatus,
          'new_status': serverStatus,
          'server_reason': serverReason,
          'event_type': localEvent.type,
        },
      );

      return ReconcileEventResult.updated;

    } catch (e) {
      logger.error(
        'Failed to reconcile event',
        _component,
        {
          'server_event_id': serverEvent['id'],
          'error': e.toString(),
        },
      );
      return ReconcileEventResult.error;
    }
  }

  /// Maps server status string to local EventStatus enum
  EventStatus _mapServerStatusToLocal(String serverStatus) {
    switch (serverStatus.toUpperCase()) {
      case 'CONFIRMED':
        return EventStatus.confirmed;
      case 'REJECTED':
        return EventStatus.rejected;
      case 'PENDING':
        return EventStatus.pending;
      default:
        logger.warn(
          'Unknown server status',
          _component,
          {'status': serverStatus},
        );
        return EventStatus.pending;
    }
  }

  /// Gets the last reconciliation timestamp
  Future<DateTime?> getLastReconcileTime() async {
    return await _syncCursorRepo.getLastSynced(_cursorKey);
  }
}

/// Result of a reconciliation operation
class ReconcileResult {
  final int eventsChecked;
  final int eventsUpdated;
  final int eventsMissing;
  final Duration duration;
  final bool success;
  final String? error;

  ReconcileResult({
    required this.eventsChecked,
    required this.eventsUpdated,
    required this.eventsMissing,
    required this.duration,
    required this.success,
    this.error,
  });

  @override
  String toString() {
    if (success) {
      return 'ReconcileResult(checked: $eventsChecked, updated: $eventsUpdated, '
             'missing: $eventsMissing, duration: ${duration.inMilliseconds}ms)';
    } else {
      return 'ReconcileResult(failed: $error)';
    }
  }
}

/// Result of reconciling a single event
enum ReconcileEventResult {
  updated,   // Event status was updated to match server
  unchanged, // Event status already matches server (idempotent)
  missing,   // Local event not found for server event
  skipped,   // Event was skipped (e.g., missing client_event_id)
  error,     // Error occurred during reconciliation
}

