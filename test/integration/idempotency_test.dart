import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:attend_proto/data/local/db.dart';
import 'package:attend_proto/data/local/event_log_repo.dart';
import 'package:attend_proto/data/local/outbox_repo.dart';

void main() {
  group('Idempotency & Deduplication', () {
    late AppDatabase database;
    late EventLogRepo eventLogRepo;
    late OutboxRepo outboxRepo;

    setUp(() {
      database = AppDatabase.withExecutor(NativeDatabase.memory());
      eventLogRepo = EventLogRepo(database);
      outboxRepo = OutboxRepo(database);
    });

    tearDown(() async {
      await database.close();
    });

    group('Dedupe Key Enforcement', () {
      test('duplicate dedupe_key is rejected', () async {
        const dedupeKey = 'session-123_device-456_ATTEND_IN_1234567890';

        // First enqueue should succeed
        final id1 = await outboxRepo.enqueue(
          eventId: 'event-1',
          dedupeKey: dedupeKey,
          endpoint: '/api/attendance/validate',
          method: 'POST',
          payload: {'test': 'data'},
        );

        expect(id1, isNotEmpty);

        // Second enqueue with same dedupe_key should fail
        expect(
          () async => await outboxRepo.enqueue(
            eventId: 'event-2',
            dedupeKey: dedupeKey,
            endpoint: '/api/attendance/validate',
            method: 'POST',
            payload: {'test': 'data2'},
          ),
          throwsA(isA<DuplicateDedupeKeyException>()),
        );
      });

      test('different dedupe_keys are allowed', () async {
        final id1 = await outboxRepo.enqueue(
          eventId: 'event-1',
          dedupeKey: 'session-123_device-456_ATTEND_IN_1234567890',
          endpoint: '/api/attendance/validate',
          method: 'POST',
          payload: {'test': 'data1'},
        );

        final id2 = await outboxRepo.enqueue(
          eventId: 'event-2',
          dedupeKey: 'session-123_device-456_ATTEND_OUT_1234567999',
          endpoint: '/api/attendance/validate',
          method: 'POST',
          payload: {'test': 'data2'},
        );

        expect(id1, isNotEmpty);
        expect(id2, isNotEmpty);
        expect(id1, isNot(equals(id2)));
      });

      test('dedupe_key is unique per event type and timestamp', () async {
        // Sign-in at time T
        final id1 = await outboxRepo.enqueue(
          eventId: 'event-1',
          dedupeKey: 'session-123_device-456_ATTEND_IN_1000',
          endpoint: '/api/attendance/validate',
          method: 'POST',
          payload: {},
        );

        // Sign-out at time T (different type)
        final id2 = await outboxRepo.enqueue(
          eventId: 'event-2',
          dedupeKey: 'session-123_device-456_ATTEND_OUT_1000',
          endpoint: '/api/attendance/validate',
          method: 'POST',
          payload: {},
        );

        // Sign-in at time T+1 (different timestamp)
        final id3 = await outboxRepo.enqueue(
          eventId: 'event-3',
          dedupeKey: 'session-123_device-456_ATTEND_IN_1001',
          endpoint: '/api/attendance/validate',
          method: 'POST',
          payload: {},
        );

        expect(id1, isNotEmpty);
        expect(id2, isNotEmpty);
        expect(id3, isNotEmpty);
        
        // All should be different
        expect(id1, isNot(equals(id2)));
        expect(id1, isNot(equals(id3)));
        expect(id2, isNot(equals(id3)));
      });
    });

    group('Outbox Item Retrieval', () {
      test('only items ready for retry are dequeued', () async {
        // Item 1: Ready now
        await outboxRepo.enqueue(
          eventId: 'event-1',
          dedupeKey: 'dedupe-1',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );

        // Item 2: Scheduled for future
        final id2 = await outboxRepo.enqueue(
          eventId: 'event-2',
          dedupeKey: 'dedupe-2',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );
        
        // Schedule item 2 for 1 hour in the future
        await outboxRepo.scheduleNextAttempt(
          id2,
          DateTime.now().add(const Duration(hours: 1)),
        );

        // Only item 1 should be dequeued
        final batch = await outboxRepo.dequeueBatch(limit: 10);
        expect(batch.length, equals(1));
        expect(batch.first.eventId, equals('event-1'));
      });

      test('items are dequeued in chronological order', () async {
        // Create items with different next attempt times
        await outboxRepo.enqueue(
          eventId: 'event-3',
          dedupeKey: 'dedupe-3',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );

        await outboxRepo.enqueue(
          eventId: 'event-1',
          dedupeKey: 'dedupe-1',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );

        await outboxRepo.enqueue(
          eventId: 'event-2',
          dedupeKey: 'dedupe-2',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );

        final batch = await outboxRepo.dequeueBatch(limit: 10);
        expect(batch.length, equals(3));
        
        // Should be ordered by nextAttemptAt (all are now, so insertion order)
        expect(batch[0].eventId, equals('event-3'));
        expect(batch[1].eventId, equals('event-1'));
        expect(batch[2].eventId, equals('event-2'));
      });

      test('batch limit is respected', () async {
        // Create 5 items
        for (int i = 0; i < 5; i++) {
          await outboxRepo.enqueue(
            eventId: 'event-$i',
            dedupeKey: 'dedupe-$i',
            endpoint: '/api/test',
            method: 'POST',
            payload: {},
          );
        }

        // Request only 3
        final batch = await outboxRepo.dequeueBatch(limit: 3);
        expect(batch.length, equals(3));
      });
    });

    group('Event Log Deduplication', () {
      test('multiple events can have same type', () async {
        final id1 = await eventLogRepo.append(
          EventType.attendIn,
          {'timestamp': '2024-01-01T10:00:00Z'},
        );

        final id2 = await eventLogRepo.append(
          EventType.attendIn,
          {'timestamp': '2024-01-01T11:00:00Z'},
        );

        expect(id1, isNotEmpty);
        expect(id2, isNotEmpty);
        expect(id1, isNot(equals(id2)));
      });

      test('events have unique IDs', () async {
        final ids = <String>[];
        
        for (int i = 0; i < 10; i++) {
          final id = await eventLogRepo.append(
            EventType.heartbeat,
            {'timestamp': DateTime.now().toIso8601String()},
          );
          ids.add(id);
        }

        // All IDs should be unique
        final uniqueIds = ids.toSet();
        expect(uniqueIds.length, equals(10));
      });
    });

    group('Retry Attempt Tracking', () {
      test('attempt count increments correctly', () async {
        final id = await outboxRepo.enqueue(
          eventId: 'event-1',
          dedupeKey: 'dedupe-1',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );

        // Initial attempts should be 0
        final items = await outboxRepo.getAllItems();
        expect(items.first.attempts, equals(0));

        // Mark first attempt
        await outboxRepo.markAttempt(id, error: 'Network timeout');
        
        final items2 = await outboxRepo.getAllItems();
        expect(items2.first.attempts, equals(1));

        // Mark second attempt
        await outboxRepo.markAttempt(id, error: 'Connection refused');
        
        final items3 = await outboxRepo.getAllItems();
        expect(items3.first.attempts, equals(2));
      });

      test('last error is recorded', () async {
        final id = await outboxRepo.enqueue(
          eventId: 'event-1',
          dedupeKey: 'dedupe-1',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );

        await outboxRepo.markAttempt(id, error: 'Network timeout');
        
        final items = await outboxRepo.getAllItems();
        expect(items.first.lastError, equals('Network timeout'));
      });
    });

    group('Successful Sync Cleanup', () {
      test('successful items are removed from outbox', () async {
        final id = await outboxRepo.enqueue(
          eventId: 'event-1',
          dedupeKey: 'dedupe-1',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );

        // Verify item exists
        final itemsBefore = await outboxRepo.getAllItems();
        expect(itemsBefore.length, equals(1));

        // Remove item (simulating successful sync)
        await outboxRepo.removeItem(id);

        // Verify item is gone
        final itemsAfter = await outboxRepo.getAllItems();
        expect(itemsAfter.length, equals(0));
      });

      test('removing item does not affect event log', () async {
        // Create event
        final eventId = await eventLogRepo.append(
          EventType.attendIn,
          {'timestamp': DateTime.now().toIso8601String()},
        );

        // Create outbox item
        final outboxId = await outboxRepo.enqueue(
          eventId: eventId,
          dedupeKey: 'dedupe-1',
          endpoint: '/api/test',
          method: 'POST',
          payload: {},
        );

        // Remove outbox item
        await outboxRepo.removeItem(outboxId);

        // Event should still exist
        final events = await eventLogRepo.getEvents();
        expect(events.length, equals(1));
        expect(events.first.id, equals(eventId));
      });
    });
  });
}

