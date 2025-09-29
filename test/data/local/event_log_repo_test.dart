import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import '../../../lib/data/local/db.dart';
import '../../../lib/data/local/event_log_repo.dart';

void main() {
  late AppDatabase database;
  late EventLogRepo eventLogRepo;

  setUp(() {
    // Use in-memory database for tests
    database = createTestDatabase();
    eventLogRepo = EventLogRepo(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('EventLogRepo', () {
    test('append creates event with PENDING status', () async {
      // Arrange
      final payload = {'location': 'test', 'timestamp': '2024-01-01'};

      // Act
      final eventId = await eventLogRepo.append(EventType.attendIn, payload);

      // Assert
      expect(eventId, isNotEmpty);
      
      final event = await eventLogRepo.getEventById(eventId);
      expect(event, isNotNull);
      expect(event!.type, EventType.attendIn.value);
      expect(event.status, EventStatus.pending.value);
      expect(event.serverReason, isNull);
    });

    test('markStatus updates event status and reason', () async {
      // Arrange
      final payload = {'location': 'test'};
      final eventId = await eventLogRepo.append(EventType.attendOut, payload);

      // Act
      await eventLogRepo.markStatus(eventId, EventStatus.confirmed, 'Server approved');

      // Assert
      final event = await eventLogRepo.getEventById(eventId);
      expect(event!.status, EventStatus.confirmed.value);
      expect(event.serverReason, 'Server approved');
    });

    test('getEvents returns all events', () async {
      // Arrange
      final payload1 = {'test': '1'};
      final payload2 = {'test': '2'};
      
      final eventId1 = await eventLogRepo.append(EventType.attendIn, payload1);
      final eventId2 = await eventLogRepo.append(EventType.attendOut, payload2);

      // Act
      final events = await eventLogRepo.getEvents();

      // Assert
      expect(events.length, 2);
      final eventIds = events.map((e) => e.id).toSet();
      expect(eventIds.contains(eventId1), true);
      expect(eventIds.contains(eventId2), true);
    });

    test('getEvents filters by status', () async {
      // Arrange
      final payload = {'test': 'data'};
      final eventId1 = await eventLogRepo.append(EventType.attendIn, payload);
      final eventId2 = await eventLogRepo.append(EventType.attendOut, payload);
      
      await eventLogRepo.markStatus(eventId1, EventStatus.confirmed);
      // eventId2 remains PENDING

      // Act
      final pendingEvents = await eventLogRepo.getEvents(status: EventStatus.pending);
      final confirmedEvents = await eventLogRepo.getEvents(status: EventStatus.confirmed);

      // Assert
      expect(pendingEvents.length, 1);
      expect(pendingEvents[0].id, eventId2);
      expect(confirmedEvents.length, 1);
      expect(confirmedEvents[0].id, eventId1);
    });

    test('getCountByStatus returns correct counts', () async {
      // Arrange
      final payload = {'test': 'data'};
      final eventId1 = await eventLogRepo.append(EventType.attendIn, payload);
      final eventId2 = await eventLogRepo.append(EventType.attendOut, payload);
      final eventId3 = await eventLogRepo.append(EventType.heartbeat, payload);
      
      await eventLogRepo.markStatus(eventId1, EventStatus.confirmed);
      await eventLogRepo.markStatus(eventId2, EventStatus.rejected);
      // eventId3 remains PENDING

      // Act & Assert
      expect(await eventLogRepo.getCountByStatus(EventStatus.pending), 1);
      expect(await eventLogRepo.getCountByStatus(EventStatus.confirmed), 1);
      expect(await eventLogRepo.getCountByStatus(EventStatus.rejected), 1);
    });

    test('deleteOldEvents works correctly', () async {
      // Arrange
      final payload = {'test': 'data'};
      await eventLogRepo.append(EventType.attendIn, payload);
      
      // Verify event exists
      final initialEvents = await eventLogRepo.getEvents();
      expect(initialEvents.length, 1);
      
      // Act - delete events older than a very long time (should delete nothing)
      final deletedCount = await eventLogRepo.deleteOldEvents(const Duration(days: 1));
      expect(deletedCount, 0); // No events should be deleted
      
      // Delete events older than negative duration (should delete all)
      final deletedCountAll = await eventLogRepo.deleteOldEvents(const Duration(seconds: -1));
      expect(deletedCountAll, 1); // Event should be deleted
      
      final remainingEvents = await eventLogRepo.getEvents();
      expect(remainingEvents.length, 0); // No events should remain
    });

    test('getEvents respects limit parameter', () async {
      // Arrange
      final payload = {'test': 'data'};
      for (int i = 0; i < 5; i++) {
        await eventLogRepo.append(EventType.attendIn, payload);
      }

      // Act
      final limitedEvents = await eventLogRepo.getEvents(limit: 3);

      // Assert
      expect(limitedEvents.length, 3);
    });
  });
}

// Helper to create test database
AppDatabase createTestDatabase() {
  return AppDatabase.withExecutor(NativeDatabase.memory());
}
