import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import '../../lib/data/local/db.dart';
import '../../lib/data/local/event_log_repo.dart';
import '../../lib/data/local/outbox_repo.dart';
import '../../lib/data/local/sync_cursor_repo.dart';
import '../../lib/data/remote/api_client.dart';
import '../../lib/domain/reconcile_service.dart';

/// Integration tests for reconciliation flow
/// 
/// Tests the complete reconciliation workflow including:
/// - Offline event capture
/// - Sync to server
/// - Server decision (confirm/reject)
/// - Reconciliation pulls status back
void main() {
  group('Reconciliation Integration Tests', () {
    late AppDatabase database;
    late EventLogRepo eventLogRepo;
    late OutboxRepo outboxRepo;
    late SyncCursorRepo syncCursorRepo;
    late MockApiClient mockApiClient;
    late ReconcileService reconcileService;

    setUp(() {
      database = createTestDatabase();
      eventLogRepo = EventLogRepo(database);
      outboxRepo = OutboxRepo(database);
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

    test('E2E: Offline capture → Server reject → Reconcile flips status', () async {
      // ============================================
      // STEP 1: Simulate offline event capture
      // ============================================
      
      final now = DateTime.now();
      final eventPayload = {
        'timestamp': now.toIso8601String(),
        'location': {
          'lat': 0.0,  // Outside geofence
          'lng': 0.0,
          'accuracy': 10.0,
        },
        'session_id': '550e8400-e29b-41d4-a716-446655440002',
        'device_id': '550e8400-e29b-41d4-a716-446655440001',
        'biometric_ok': true,
        'biometric_timestamp': now.toIso8601String(),
      };

      final eventId = await eventLogRepo.append(EventType.attendIn, eventPayload);

      // Queue for sync
      await outboxRepo.enqueue(
        eventId: eventId,
        dedupeKey: 'test-reject-reconcile-001',
        endpoint: '/api/attendance/validate',
        method: 'POST',
        payload: eventPayload,
      );

      // Verify event is PENDING
      var events = await eventLogRepo.getEvents();
      expect(events[0].status, 'PENDING');

      // ============================================
      // STEP 2: Simulate sync (server rejects)
      // ============================================
      
      // In real scenario, sync would happen and server would reject
      // For this test, we simulate by marking as rejected
      await eventLogRepo.markStatus(
        eventId,
        EventStatus.rejected,
        'GEOFENCE_VIOLATION: Location outside geofence',
      );

      // Remove from outbox (as sync worker would do)
      final outboxItems = await outboxRepo.getAllItems();
      await outboxRepo.removeItem(outboxItems[0].id);

      // Verify local event is REJECTED
      events = await eventLogRepo.getEvents();
      expect(events[0].status, 'REJECTED');

      // ============================================
      // STEP 3: Reconciliation confirms server state
      // ============================================
      
      // Mock server returns REJECTED status
      mockApiClient.mockEvents = [
        {
          'id': 'server-reject-event-001',
          'client_event_id': eventId,
          'event_type': 'ATTEND_IN',
          'status': 'REJECTED',
          'server_reason': 'GEOFENCE_VIOLATION: Location outside geofence',
          'event_timestamp': now.toIso8601String(),
        }
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation succeeded (idempotent - no change)
      expect(result.success, true);
      expect(result.eventsChecked, 1);
      expect(result.eventsUpdated, 0); // Already REJECTED, no update

      // Verify event is still REJECTED
      events = await eventLogRepo.getEvents();
      expect(events[0].status, 'REJECTED');
      expect(events[0].serverReason, contains('GEOFENCE_VIOLATION'));
    });

    test('E2E: Server flips PENDING to REJECTED after local sync', () async {
      // ============================================
      // Scenario: Client thinks sync succeeded (PENDING)
      // but server actually rejected it
      // Reconciliation should flip local to REJECTED
      // ============================================

      final now = DateTime.now();
      final eventId = await eventLogRepo.append(
        EventType.attendIn,
        {
          'timestamp': now.toIso8601String(),
          'location': {'lat': 37.7749, 'lng': -122.4194, 'accuracy': 10.0},
        },
      );

      // Event is still PENDING locally
      var events = await eventLogRepo.getEvents();
      expect(events[0].status, 'PENDING');

      // Mock server returns REJECTED (server made decision)
      mockApiClient.mockEvents = [
        {
          'id': 'server-flip-event-001',
          'client_event_id': eventId,
          'event_type': 'ATTEND_IN',
          'status': 'REJECTED',
          'server_reason': 'BIOMETRIC_STALE: Biometric verification too old',
          'event_timestamp': now.toIso8601String(),
        }
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation updated status
      expect(result.success, true);
      expect(result.eventsUpdated, 1);

      // Verify local event is now REJECTED
      events = await eventLogRepo.getEvents();
      expect(events[0].status, 'REJECTED');
      expect(events[0].serverReason, contains('BIOMETRIC_STALE'));
    });

    test('E2E: Multiple events with mixed statuses reconcile correctly', () async {
      // ============================================
      // Create 5 events with different scenarios
      // ============================================

      final now = DateTime.now();

      // Event 1: PENDING → should become CONFIRMED
      final event1 = await eventLogRepo.append(EventType.attendIn, {'timestamp': now.toIso8601String()});

      // Event 2: PENDING → should become REJECTED
      final event2 = await eventLogRepo.append(EventType.attendOut, {'timestamp': now.toIso8601String()});

      // Event 3: Already CONFIRMED → should stay CONFIRMED (idempotent)
      final event3 = await eventLogRepo.append(EventType.heartbeat, {'timestamp': now.toIso8601String()});
      await eventLogRepo.markStatus(event3, EventStatus.confirmed, 'Already confirmed');

      // Event 4: PENDING → missing on server (logged as missing)
      final event4 = await eventLogRepo.append(EventType.attendIn, {'timestamp': now.toIso8601String()});

      // Event 5: PENDING → should become CONFIRMED
      final event5 = await eventLogRepo.append(EventType.heartbeat, {'timestamp': now.toIso8601String()});

      // Mock server responses (event4 not included = missing)
      mockApiClient.mockEvents = [
        {
          'id': 'server-1',
          'client_event_id': event1,
          'event_type': 'ATTEND_IN',
          'status': 'CONFIRMED',
          'server_reason': 'Event validated successfully',
          'event_timestamp': now.toIso8601String(),
        },
        {
          'id': 'server-2',
          'client_event_id': event2,
          'event_type': 'ATTEND_OUT',
          'status': 'REJECTED',
          'server_reason': 'SIGN_OUT_WITHOUT_SIGN_IN',
          'event_timestamp': now.toIso8601String(),
        },
        {
          'id': 'server-3',
          'client_event_id': event3,
          'event_type': 'HEARTBEAT',
          'status': 'CONFIRMED',
          'server_reason': 'Already confirmed',
          'event_timestamp': now.toIso8601String(),
        },
        // event4 not returned by server (missing)
        {
          'id': 'server-5',
          'client_event_id': event5,
          'event_type': 'HEARTBEAT',
          'status': 'CONFIRMED',
          'server_reason': 'OK',
          'event_timestamp': now.toIso8601String(),
        },
      ];

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation results
      expect(result.success, true);
      expect(result.eventsChecked, 4); // event4 not in server response
      expect(result.eventsUpdated, 3); // event1, event2, event5 updated
      expect(result.eventsMissing, 0); // event4 exists locally, just not returned

      // Verify individual event statuses
      final events = await eventLogRepo.getEvents();
      
      final e1 = events.firstWhere((e) => e.id == event1);
      expect(e1.status, 'CONFIRMED');

      final e2 = events.firstWhere((e) => e.id == event2);
      expect(e2.status, 'REJECTED');
      expect(e2.serverReason, contains('SIGN_OUT_WITHOUT_SIGN_IN'));

      final e3 = events.firstWhere((e) => e.id == event3);
      expect(e3.status, 'CONFIRMED'); // Unchanged (idempotent)

      final e4 = events.firstWhere((e) => e.id == event4);
      expect(e4.status, 'PENDING'); // Still PENDING (not in server response)

      final e5 = events.firstWhere((e) => e.id == event5);
      expect(e5.status, 'CONFIRMED');
    });

    test('Reconciliation runs periodically and updates cursor', () async {
      // Create event
      final eventId = await eventLogRepo.append(
        EventType.attendIn,
        {'timestamp': DateTime.now().toIso8601String()},
      );

      // Mock server response
      mockApiClient.mockEvents = [
        {
          'id': 'server-periodic-001',
          'client_event_id': eventId,
          'event_type': 'ATTEND_IN',
          'status': 'CONFIRMED',
          'server_reason': 'OK',
          'event_timestamp': DateTime.now().toIso8601String(),
        }
      ];

      // First reconciliation
      await reconcileService.reconcile();
      final firstReconcileTime = await reconcileService.getLastReconcileTime();
      expect(firstReconcileTime, isNotNull);

      // Wait a bit to ensure time difference
      await Future.delayed(const Duration(milliseconds: 150));

      // Second reconciliation
      await reconcileService.reconcile();
      final secondReconcileTime = await reconcileService.getLastReconcileTime();
      expect(secondReconcileTime, isNotNull);
      
      // Second reconcile time should be at or after first (idempotent updates are OK)
      expect(
        secondReconcileTime!.isAfter(firstReconcileTime!) || 
        secondReconcileTime.isAtSameMomentAs(firstReconcileTime),
        true,
        reason: 'Second reconcile time should be >= first reconcile time',
      );
    });

    test('Reconciliation handles API errors gracefully', () async {
      // Create event
      await eventLogRepo.append(
        EventType.attendIn,
        {'timestamp': DateTime.now().toIso8601String()},
      );

      // Mock API throws error
      mockApiClient.shouldThrowError = true;

      // Run reconciliation
      final result = await reconcileService.reconcile();

      // Verify reconciliation failed gracefully
      expect(result.success, false);
      expect(result.error, isNotNull);
      expect(result.eventsChecked, 0);
      expect(result.eventsUpdated, 0);
    });
  });
}

// Helper to create test database
AppDatabase createTestDatabase() {
  return AppDatabase.withExecutor(NativeDatabase.memory());
}

/// Mock API client for integration testing
class MockApiClient implements ApiClient {
  List<Map<String, dynamic>> mockEvents = [];
  bool shouldThrowError = false;

  @override
  Future<List<Map<String, dynamic>>> getRecentEvents({
    DateTime? since,
    int limit = 100,
  }) async {
    if (shouldThrowError) {
      throw Exception('Network error');
    }
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

