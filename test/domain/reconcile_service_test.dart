import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import '../../lib/data/local/db.dart';
import '../../lib/data/local/event_log_repo.dart';
import '../../lib/data/local/sync_cursor_repo.dart';
import '../../lib/data/remote/api_client.dart';
import '../../lib/domain/reconcile_service.dart';

/// Unit tests for ReconcileService
/// 
/// Tests the reconciliation logic that syncs server event statuses
/// back to the local database.
void main() {
  group('ReconcileService', () {
    late AppDatabase database;
    late EventLogRepo eventLogRepo;
    late SyncCursorRepo syncCursorRepo;
    late MockApiClient mockApiClient;
    late ReconcileService reconcileService;

    setUp(() {
      database = createTestDatabase();
      eventLogRepo = EventLogRepo(database);
      syncCursorRepo = SyncCursorRepo(database);
      mockApiClient = MockApiClient();
      
      reconcileService = ReconcileService(
        eventLogRepo: eventLogRepo,
        syncCursorRepo: syncCursorRepo,
        apiClient: mockApiClient,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('reconcile updates local PENDING event to CONFIRMED', () async {
      // Create local pending event
      final eventId = await eventLogRepo.append(
        EventType.attendIn,
        {
          'timestamp': DateTime.now().toIso8601String(),
          'location': {'lat': 37.7749, 'lng': -122.4194, 'accuracy': 10.0},
        },
      );

      expect(eventId, isNotEmpty);

      // Verify event is PENDING
      var events = await eventLogRepo.getEvents();
      expect(events[0].status, 'PENDING');

      // Mock server returns CONFIRMED
      mockApiClient.mockEvents = [
        {
          'id': 'server-event-id-123',
          'client_event_id': eventId,
          'event_type': 'ATTEND_IN',
          'status': 'CONFIRMED',
          'server_reason': 'Event validated successfully',
          'event_timestamp': DateTime.now().toIso8601String(),
        }
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation succeeded
      expect(result.success, true);
      expect(result.eventsChecked, 1);
      expect(result.eventsUpdated, 1);
      expect(result.eventsMissing, 0);

      // Verify local event is now CONFIRMED
      events = await eventLogRepo.getEvents();
      expect(events[0].status, 'CONFIRMED');
      expect(events[0].serverReason, 'Event validated successfully');
    });

    test('reconcile updates local PENDING event to REJECTED', () async {
      // Create local pending event
      final eventId = await eventLogRepo.append(
        EventType.attendIn,
        {
          'timestamp': DateTime.now().toIso8601String(),
          'location': {'lat': 0.0, 'lng': 0.0, 'accuracy': 10.0}, // Outside geofence
        },
      );

      // Mock server returns REJECTED
      mockApiClient.mockEvents = [
        {
          'id': 'server-event-id-456',
          'client_event_id': eventId,
          'event_type': 'ATTEND_IN',
          'status': 'REJECTED',
          'server_reason': 'GEOFENCE_VIOLATION: Location outside geofence',
          'event_timestamp': DateTime.now().toIso8601String(),
        }
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation succeeded
      expect(result.success, true);
      expect(result.eventsUpdated, 1);

      // Verify local event is now REJECTED with reason
      final events = await eventLogRepo.getEvents();
      expect(events[0].status, 'REJECTED');
      expect(events[0].serverReason, contains('GEOFENCE_VIOLATION'));
    });

    test('reconcile is idempotent (no update if status matches)', () async {
      // Create local event and mark it as CONFIRMED
      final eventId = await eventLogRepo.append(
        EventType.attendIn,
        {'timestamp': DateTime.now().toIso8601String()},
      );
      await eventLogRepo.markStatus(eventId, EventStatus.confirmed, 'Already confirmed');

      // Mock server also returns CONFIRMED
      mockApiClient.mockEvents = [
        {
          'id': 'server-event-id-789',
          'client_event_id': eventId,
          'event_type': 'ATTEND_IN',
          'status': 'CONFIRMED',
          'server_reason': 'Event validated successfully',
          'event_timestamp': DateTime.now().toIso8601String(),
        }
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify no updates were made (idempotent)
      expect(result.success, true);
      expect(result.eventsChecked, 1);
      expect(result.eventsUpdated, 0); // No update needed
      expect(result.eventsMissing, 0);

      // Verify event status is still CONFIRMED
      final events = await eventLogRepo.getEvents();
      expect(events[0].status, 'CONFIRMED');
    });

    test('reconcile handles missing local event gracefully', () async {
      // Mock server returns an event that doesn't exist locally
      mockApiClient.mockEvents = [
        {
          'id': 'server-event-id-999',
          'client_event_id': 'non-existent-event-id',
          'event_type': 'ATTEND_IN',
          'status': 'CONFIRMED',
          'server_reason': 'Event validated successfully',
          'event_timestamp': DateTime.now().toIso8601String(),
        }
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation succeeded but reported missing event
      expect(result.success, true);
      expect(result.eventsChecked, 1);
      expect(result.eventsUpdated, 0);
      expect(result.eventsMissing, 1);
    });

    test('reconcile handles server event without client_event_id', () async {
      // Mock server returns an event without client_event_id (skipped)
      mockApiClient.mockEvents = [
        {
          'id': 'server-event-id-888',
          'client_event_id': null, // Missing
          'event_type': 'ATTEND_IN',
          'status': 'CONFIRMED',
          'event_timestamp': DateTime.now().toIso8601String(),
        }
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation succeeded but skipped the event
      expect(result.success, true);
      expect(result.eventsChecked, 1);
      expect(result.eventsUpdated, 0);
      expect(result.eventsMissing, 0);
    });

    test('reconcile handles multiple events in batch', () async {
      // Create 3 local events
      final eventId1 = await eventLogRepo.append(EventType.attendIn, {'timestamp': DateTime.now().toIso8601String()});
      final eventId2 = await eventLogRepo.append(EventType.attendOut, {'timestamp': DateTime.now().toIso8601String()});
      final eventId3 = await eventLogRepo.append(EventType.heartbeat, {'timestamp': DateTime.now().toIso8601String()});

      // Mock server returns mixed statuses
      mockApiClient.mockEvents = [
        {
          'id': 'server-1',
          'client_event_id': eventId1,
          'event_type': 'ATTEND_IN',
          'status': 'CONFIRMED',
          'server_reason': 'OK',
          'event_timestamp': DateTime.now().toIso8601String(),
        },
        {
          'id': 'server-2',
          'client_event_id': eventId2,
          'event_type': 'ATTEND_OUT',
          'status': 'REJECTED',
          'server_reason': 'Sequence error',
          'event_timestamp': DateTime.now().toIso8601String(),
        },
        {
          'id': 'server-3',
          'client_event_id': eventId3,
          'event_type': 'HEARTBEAT',
          'status': 'CONFIRMED',
          'server_reason': 'OK',
          'event_timestamp': DateTime.now().toIso8601String(),
        },
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify all 3 events were processed
      expect(result.success, true);
      expect(result.eventsChecked, 3);
      expect(result.eventsUpdated, 3);

      // Verify individual statuses
      final events = await eventLogRepo.getEvents();
      final event1 = events.firstWhere((e) => e.id == eventId1);
      final event2 = events.firstWhere((e) => e.id == eventId2);
      final event3 = events.firstWhere((e) => e.id == eventId3);

      expect(event1.status, 'CONFIRMED');
      expect(event2.status, 'REJECTED');
      expect(event3.status, 'CONFIRMED');
    });

    test('reconcile updates sync cursor', () async {
      // Run reconciliation
      await reconcileService.reconcile();

      // Verify cursor was updated
      final lastReconcile = await reconcileService.getLastReconcileTime();
      expect(lastReconcile, isNotNull);
      expect(lastReconcile!.isBefore(DateTime.now()), true);
    });

    test('reconcile handles empty server response', () async {
      // Mock server returns no events
      mockApiClient.mockEvents = [];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation succeeded with no events
      expect(result.success, true);
      expect(result.eventsChecked, 0);
      expect(result.eventsUpdated, 0);
      expect(result.eventsMissing, 0);
    });

    test('reconcile uses last reconcile time for fetching', () async {
      // Set last reconcile time to 1 hour ago
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
      await syncCursorRepo.setLastSynced('last_reconcile_at', oneHourAgo);

      // Run reconciliation
      await reconcileService.reconcile();

      // Verify mockApiClient was called with correct 'since' parameter
      expect(mockApiClient.lastSinceParam, isNotNull);
      expect(mockApiClient.lastSinceParam!.isAfter(oneHourAgo.subtract(const Duration(seconds: 1))), true);
    });
  });
}

// Helper to create test database
AppDatabase createTestDatabase() {
  return AppDatabase.withExecutor(NativeDatabase.memory());
}

/// Mock API client for testing
class MockApiClient implements ApiClient {
  List<Map<String, dynamic>> mockEvents = [];
  DateTime? lastSinceParam;

  @override
  Future<List<Map<String, dynamic>>> getRecentEvents({
    DateTime? since,
    int limit = 100,
  }) async {
    lastSinceParam = since;
    return mockEvents;
  }

  @override
  Future<ApiResponse> postAttendance({
    required String eventId,
    required String eventType,
    required String dedupeKey,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool biometricOk,
    DateTime? biometricTimestamp,
  }) async {
    throw UnimplementedError('Not used in reconcile tests');
  }

  @override
  Future<ApiResponse> postHeartbeat({
    required String eventId,
    required String dedupeKey,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    throw UnimplementedError('Not used in reconcile tests');
  }
}

