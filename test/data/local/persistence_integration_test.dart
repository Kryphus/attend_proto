import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import '../../../lib/data/local/db.dart';
import '../../../lib/data/local/event_log_repo.dart';
import '../../../lib/data/local/outbox_repo.dart';
import '../../../lib/data/local/sync_cursor_repo.dart';

void main() {
  group('Persistence Integration Tests', () {
    late String testDbPath;

    setUp(() {
      // Create a temporary database file for testing
      testDbPath = p.join(Directory.systemTemp.path, 'test_${DateTime.now().millisecondsSinceEpoch}.db');
    });

    tearDown(() {
      // Clean up test database file
      final file = File(testDbPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    test('data persists across database close and reopen', () async {
      // Phase 1: Create database, add data, close
      late String eventId;
      late String outboxId;
      const syncKey = 'test_sync';
      final syncTime = DateTime.now();

      {
        final database = AppDatabase.withExecutor(NativeDatabase(File(testDbPath)));
        final eventLogRepo = EventLogRepo(database);
        final outboxRepo = OutboxRepo(database);
        final syncCursorRepo = SyncCursorRepo(database);

        // Add event log entry
        eventId = await eventLogRepo.append(
          EventType.attendIn,
          {'location': 'test_location', 'accuracy': 5.0},
        );

        // Add outbox entry
        outboxId = await outboxRepo.enqueue(
          eventId: eventId,
          dedupeKey: 'test_dedupe_key',
          endpoint: '/api/attendance',
          method: 'POST',
          payload: {'event_id': eventId},
        );

        // Add sync cursor
        await syncCursorRepo.setLastSynced(syncKey, syncTime);

        // Verify data exists
        final events = await eventLogRepo.getEvents();
        expect(events.length, 1);
        expect(events[0].id, eventId);

        final outboxItems = await outboxRepo.getAllItems();
        expect(outboxItems.length, 1);
        expect(outboxItems[0].id, outboxId);

        final lastSynced = await syncCursorRepo.getLastSynced(syncKey);
        expect(lastSynced, isNotNull);

        await database.close();
      }

      // Phase 2: Reopen database, verify data persists
      {
        final database = AppDatabase.withExecutor(NativeDatabase(File(testDbPath)));
        final eventLogRepo = EventLogRepo(database);
        final outboxRepo = OutboxRepo(database);
        final syncCursorRepo = SyncCursorRepo(database);

        // Verify event log data persisted
        final events = await eventLogRepo.getEvents();
        expect(events.length, 1);
        expect(events[0].id, eventId);
        expect(events[0].type, EventType.attendIn.value);
        expect(events[0].status, EventStatus.pending.value);

        // Verify outbox data persisted
        final outboxItems = await outboxRepo.getAllItems();
        expect(outboxItems.length, 1);
        expect(outboxItems[0].id, outboxId);
        expect(outboxItems[0].eventId, eventId);
        expect(outboxItems[0].dedupeKey, 'test_dedupe_key');

        // Verify sync cursor data persisted
        final lastSynced = await syncCursorRepo.getLastSynced(syncKey);
        expect(lastSynced, isNotNull);
        expect(lastSynced!.millisecondsSinceEpoch, syncTime.millisecondsSinceEpoch);

        await database.close();
      }
    });

    test('database handles multiple events and maintains relationships', () async {
      final database = AppDatabase.withExecutor(NativeDatabase(File(testDbPath)));
      final eventLogRepo = EventLogRepo(database);
      final outboxRepo = OutboxRepo(database);

      try {
        // Create multiple events
        final eventId1 = await eventLogRepo.append(
          EventType.attendIn,
          {'location': 'location1'},
        );
        final eventId2 = await eventLogRepo.append(
          EventType.attendOut,
          {'location': 'location2'},
        );
        final eventId3 = await eventLogRepo.append(
          EventType.heartbeat,
          {'status': 'alive'},
        );

        // Create outbox entries for each event
        await outboxRepo.enqueue(
          eventId: eventId1,
          dedupeKey: 'dedupe1',
          endpoint: '/api/attend_in',
          method: 'POST',
          payload: {'event_id': eventId1},
        );

        await outboxRepo.enqueue(
          eventId: eventId2,
          dedupeKey: 'dedupe2',
          endpoint: '/api/attend_out',
          method: 'POST',
          payload: {'event_id': eventId2},
        );

        await outboxRepo.enqueue(
          eventId: eventId3,
          dedupeKey: 'dedupe3',
          endpoint: '/api/heartbeat',
          method: 'POST',
          payload: {'event_id': eventId3},
        );

        // Update some event statuses
        await eventLogRepo.markStatus(eventId1, EventStatus.confirmed, 'Approved by server');
        await eventLogRepo.markStatus(eventId2, EventStatus.rejected, 'Outside geofence');

        // Verify counts
        expect(await eventLogRepo.getCountByStatus(EventStatus.pending), 1);
        expect(await eventLogRepo.getCountByStatus(EventStatus.confirmed), 1);
        expect(await eventLogRepo.getCountByStatus(EventStatus.rejected), 1);

        // Verify outbox relationships
        final outboxForEvent1 = await outboxRepo.getItemsByEventId(eventId1);
        expect(outboxForEvent1.length, 1);
        expect(outboxForEvent1[0].dedupeKey, 'dedupe1');

        final outboxForEvent2 = await outboxRepo.getItemsByEventId(eventId2);
        expect(outboxForEvent2.length, 1);
        expect(outboxForEvent2[0].dedupeKey, 'dedupe2');

        // Test batch operations
        final readyItems = await outboxRepo.dequeueBatch(limit: 2);
        expect(readyItems.length, 2);

      } finally {
        await database.close();
      }
    });

    test('database handles concurrent operations correctly', () async {
      final database = AppDatabase.withExecutor(NativeDatabase(File(testDbPath)));
      final eventLogRepo = EventLogRepo(database);
      final outboxRepo = OutboxRepo(database);

      try {
        // Simulate concurrent event creation
        final futures = <Future>[];
        for (int i = 0; i < 10; i++) {
          futures.add(
            eventLogRepo.append(
              EventType.heartbeat,
              {'sequence': i},
            ).then((eventId) => outboxRepo.enqueue(
              eventId: eventId,
              dedupeKey: 'concurrent_$i',
              endpoint: '/api/heartbeat',
              method: 'POST',
              payload: {'sequence': i},
            )),
          );
        }

        await Future.wait(futures);

        // Verify all events and outbox items were created
        final events = await eventLogRepo.getEvents();
        expect(events.length, 10);

        final outboxItems = await outboxRepo.getAllItems();
        expect(outboxItems.length, 10);

        // Verify unique dedupe keys
        final dedupeKeys = outboxItems.map((item) => item.dedupeKey).toSet();
        expect(dedupeKeys.length, 10); // All should be unique

      } finally {
        await database.close();
      }
    });
  });
}
