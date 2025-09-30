import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import '../../lib/data/local/db.dart';
import '../../lib/data/local/event_log_repo.dart';
import '../../lib/data/local/outbox_repo.dart';

/// E2E Integration Test for Offline→Online Sync Flow
/// 
/// This test simulates the complete offline capture and sync process:
/// 1. Event captured offline → stored as PENDING
/// 2. Event queued in outbox
/// 3. Sync triggered (simulated)
/// 4. Event status updated based on server response
void main() {
  group('E2E Offline→Online Sync Test', () {
    late AppDatabase database;
    late EventLogRepo eventLogRepo;
    late OutboxRepo outboxRepo;

    setUp(() {
      database = createTestDatabase();
      eventLogRepo = EventLogRepo(database);
      outboxRepo = OutboxRepo(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('Complete offline capture to sync flow', () async {
      // ============================================
      // STEP 1: Simulate offline event capture
      // ============================================
      
      final now = DateTime.now();
      final testEventPayload = {
        'timestamp': now.toIso8601String(),
        'location': {
          'lat': 37.7749,
          'lng': -122.4194,
          'accuracy': 10.0,
        },
        'session_id': '550e8400-e29b-41d4-a716-446655440002',
        'device_id': '550e8400-e29b-41d4-a716-446655440001',
        'biometric_ok': true,
        'biometric_timestamp': now.toIso8601String(),
      };

      // Append event to local log (PENDING status)
      final eventId = await eventLogRepo.append(
        EventType.attendIn,
        testEventPayload,
      );

      expect(eventId, isNotEmpty);

      // Verify event is PENDING
      final events = await eventLogRepo.getEvents();
      expect(events.length, 1);
      expect(events[0].id, eventId);
      expect(events[0].status, 'PENDING');
      expect(events[0].type, 'ATTEND_IN');

      // ============================================
      // STEP 2: Queue event in outbox for sync
      // ============================================

      final dedupeKey = '550e8400-e29b-41d4-a716-446655440002-'
                        '550e8400-e29b-41d4-a716-446655440001-'
                        'ATTEND_IN-${now.toIso8601String()}';

      final outboxId = await outboxRepo.enqueue(
        eventId: eventId,
        dedupeKey: dedupeKey,
        endpoint: '/api/attendance/validate',
        method: 'POST',
        payload: {
          ...testEventPayload,
          'type': 'ATTEND_IN',
        },
      );

      expect(outboxId, isNotEmpty);

      // Verify outbox item
      final outboxItems = await outboxRepo.getAllItems();
      expect(outboxItems.length, 1);
      expect(outboxItems[0].eventId, eventId);
      expect(outboxItems[0].dedupeKey, dedupeKey);
      expect(outboxItems[0].attempts, 0);

      // ============================================
      // STEP 3: Simulate sync operation
      // ============================================

      // Get items ready for sync
      final readyItems = await outboxRepo.dequeueBatch(limit: 10);
      expect(readyItems.length, 1);
      expect(readyItems[0].id, outboxId);

      // ============================================
      // STEP 4: Simulate server CONFIRMED response
      // ============================================

      // Update event status (as sync worker would do)
      await eventLogRepo.markStatus(
        eventId,
        EventStatus.confirmed,
        'Event validated successfully',
      );

      // Remove from outbox (as sync worker would do)
      await outboxRepo.removeItem(outboxId);

      // ============================================
      // STEP 5: Verify final state
      // ============================================

      // Event should now be CONFIRMED
      final updatedEvents = await eventLogRepo.getEvents();
      expect(updatedEvents.length, 1);
      expect(updatedEvents[0].status, 'CONFIRMED');
      expect(updatedEvents[0].serverReason, 'Event validated successfully');

      // Outbox should be empty
      final remainingOutboxItems = await outboxRepo.getAllItems();
      expect(remainingOutboxItems.length, 0);

      // Verify status counts
      final confirmedCount = await eventLogRepo.getCountByStatus(EventStatus.confirmed);
      expect(confirmedCount, 1);

      final pendingCount = await eventLogRepo.getCountByStatus(EventStatus.pending);
      expect(pendingCount, 0);
    });

    test('Simulates server REJECTED response', () async {
      // ============================================
      // Simulate an event that would be rejected
      // (e.g., outside geofence)
      // ============================================

      final eventId = await eventLogRepo.append(
        EventType.attendIn,
        {
          'timestamp': DateTime.now().toIso8601String(),
          'location': {
            'lat': 0.0,  // Outside geofence
            'lng': 0.0,
            'accuracy': 10.0,
          },
        },
      );

      await outboxRepo.enqueue(
        eventId: eventId,
        dedupeKey: 'test-reject-dedupe-key',
        endpoint: '/api/attendance/validate',
        method: 'POST',
        payload: {'type': 'ATTEND_IN'},
      );

      // Simulate server rejection
      await eventLogRepo.markStatus(
        eventId,
        EventStatus.rejected,
        'GEOFENCE_VIOLATION: Location outside geofence',
      );

      // Verify event is rejected with reason
      final events = await eventLogRepo.getEvents();
      expect(events[0].status, 'REJECTED');
      expect(events[0].serverReason, contains('GEOFENCE_VIOLATION'));

      // Event should NOT be removed from database (for audit)
      final rejectedCount = await eventLogRepo.getCountByStatus(EventStatus.rejected);
      expect(rejectedCount, 1);
    });

    test('Simulates retry behavior with backoff', () async {
      // ============================================
      // Simulate a failed sync attempt with retry
      // ============================================

      final eventId = await eventLogRepo.append(
        EventType.heartbeat,
        {'timestamp': DateTime.now().toIso8601String()},
      );

      final outboxId = await outboxRepo.enqueue(
        eventId: eventId,
        dedupeKey: 'test-retry-dedupe-key',
        endpoint: '/api/heartbeat/record',
        method: 'POST',
        payload: {'type': 'HEARTBEAT'},
      );

      // Simulate first failed attempt
      await outboxRepo.markAttempt(outboxId, error: 'Network timeout');
      await outboxRepo.scheduleNextAttempt(
        outboxId,
        DateTime.now().add(const Duration(seconds: 30)),
      );

      // Verify attempt count increased
      var outboxItems = await outboxRepo.getAllItems();
      expect(outboxItems[0].attempts, 1);
      expect(outboxItems[0].lastError, 'Network timeout');

      // Item should not be ready for immediate retry
      var readyItems = await outboxRepo.dequeueBatch();
      expect(readyItems.length, 0);

      // Simulate second failed attempt
      await outboxRepo.markAttempt(outboxId, error: 'Server error 500');
      await outboxRepo.scheduleNextAttempt(
        outboxId,
        DateTime.now().add(const Duration(minutes: 2)),
      );

      // Verify backoff progression
      outboxItems = await outboxRepo.getAllItems();
      expect(outboxItems[0].attempts, 2);
      expect(outboxItems[0].lastError, 'Server error 500');

      // Finally, simulate successful sync
      await eventLogRepo.markStatus(eventId, EventStatus.confirmed, 'Success on retry');
      await outboxRepo.removeItem(outboxId);

      // Verify final state
      final events = await eventLogRepo.getEvents();
      expect(events[0].status, 'CONFIRMED');

      final remainingItems = await outboxRepo.getAllItems();
      expect(remainingItems.length, 0);
    });

    test('Verifies deduplication prevents duplicate server records', () async {
      // ============================================
      // Test that duplicate dedupe_key is caught
      // ============================================

      final eventId1 = await eventLogRepo.append(
        EventType.attendIn,
        {'timestamp': DateTime.now().toIso8601String()},
      );

      const testDedupeKey = 'duplicate-test-key-123';

      // First enqueue should succeed
      await outboxRepo.enqueue(
        eventId: eventId1,
        dedupeKey: testDedupeKey,
        endpoint: '/api/attendance/validate',
        method: 'POST',
        payload: {'type': 'ATTEND_IN'},
      );

      // Second enqueue with same dedupe_key should fail
      final eventId2 = await eventLogRepo.append(
        EventType.attendIn,
        {'timestamp': DateTime.now().toIso8601String()},
      );

      expect(
        () => outboxRepo.enqueue(
          eventId: eventId2,
          dedupeKey: testDedupeKey,
          endpoint: '/api/attendance/validate',
          method: 'POST',
          payload: {'type': 'ATTEND_IN'},
        ),
        throwsA(isA<DuplicateDedupeKeyException>()),
      );

      // Only one outbox item should exist
      final items = await outboxRepo.getAllItems();
      expect(items.length, 1);
      expect(items[0].eventId, eventId1);
    });
  });
}

// Helper to create test database
AppDatabase createTestDatabase() {
  return AppDatabase.withExecutor(NativeDatabase.memory());
}
