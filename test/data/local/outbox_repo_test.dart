import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import '../../../lib/data/local/db.dart';
import '../../../lib/data/local/outbox_repo.dart';

void main() {
  late AppDatabase database;
  late OutboxRepo outboxRepo;

  setUp(() {
    database = createTestDatabase();
    outboxRepo = OutboxRepo(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('OutboxRepo', () {
    test('enqueue creates outbox item with correct data', () async {
      // Arrange
      const eventId = 'test-event-id';
      const dedupeKey = 'test-dedupe-key';
      const endpoint = '/api/attendance';
      const method = 'POST';
      final payload = {'data': 'test'};

      // Act
      final outboxId = await outboxRepo.enqueue(
        eventId: eventId,
        dedupeKey: dedupeKey,
        endpoint: endpoint,
        method: method,
        payload: payload,
      );

      // Assert
      expect(outboxId, isNotEmpty);
      
      final items = await outboxRepo.getAllItems();
      expect(items.length, 1);
      expect(items[0].eventId, eventId);
      expect(items[0].dedupeKey, dedupeKey);
      expect(items[0].endpoint, endpoint);
      expect(items[0].method, method);
      expect(items[0].attempts, 0);
    });

    test('enqueue throws exception for duplicate dedupe key', () async {
      // Arrange
      const dedupeKey = 'duplicate-key';
      final payload = {'data': 'test'};

      await outboxRepo.enqueue(
        eventId: 'event1',
        dedupeKey: dedupeKey,
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      // Act & Assert
      expect(
        () => outboxRepo.enqueue(
          eventId: 'event2',
          dedupeKey: dedupeKey,
          endpoint: '/api/test',
          method: 'POST',
          payload: payload,
        ),
        throwsA(isA<DuplicateDedupeKeyException>()),
      );
    });

    test('dequeueBatch returns items ready for sync', () async {
      // Arrange
      final now = DateTime.now();
      final payload = {'data': 'test'};

      // Create items with different next attempt times
      await outboxRepo.enqueue(
        eventId: 'event1',
        dedupeKey: 'key1',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      await outboxRepo.enqueue(
        eventId: 'event2',
        dedupeKey: 'key2',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      // Schedule one for future
      final items = await outboxRepo.getAllItems();
      await outboxRepo.scheduleNextAttempt(
        items[1].id,
        now.add(const Duration(hours: 1)),
      );

      // Act
      final readyItems = await outboxRepo.dequeueBatch(limit: 10);

      // Assert
      expect(readyItems.length, 1);
      expect(readyItems[0].eventId, 'event1');
    });

    test('markAttempt increments attempts and sets error', () async {
      // Arrange
      final payload = {'data': 'test'};
      await outboxRepo.enqueue(
        eventId: 'event1',
        dedupeKey: 'key1',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      final items = await outboxRepo.getAllItems();
      final itemId = items[0].id;

      // Act
      await outboxRepo.markAttempt(itemId, error: 'Network timeout');

      // Assert
      final updatedItems = await outboxRepo.getAllItems();
      expect(updatedItems[0].attempts, 1);
      expect(updatedItems[0].lastError, 'Network timeout');
    });

    test('scheduleNextAttempt updates next attempt time', () async {
      // Arrange
      final payload = {'data': 'test'};
      await outboxRepo.enqueue(
        eventId: 'event1',
        dedupeKey: 'key1',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      final items = await outboxRepo.getAllItems();
      final itemId = items[0].id;
      final futureTime = DateTime.now().add(const Duration(minutes: 30));

      // Act
      await outboxRepo.scheduleNextAttempt(itemId, futureTime);

      // Assert
      final readyItems = await outboxRepo.dequeueBatch();
      expect(readyItems.length, 0); // Should not be ready yet

      final allItems = await outboxRepo.getAllItems();
      expect(allItems[0].nextAttemptAt.isAfter(DateTime.now()), true);
    });

    test('removeItem deletes item from outbox', () async {
      // Arrange
      final payload = {'data': 'test'};
      await outboxRepo.enqueue(
        eventId: 'event1',
        dedupeKey: 'key1',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      final items = await outboxRepo.getAllItems();
      expect(items.length, 1);

      // Act
      await outboxRepo.removeItem(items[0].id);

      // Assert
      final remainingItems = await outboxRepo.getAllItems();
      expect(remainingItems.length, 0);
    });

    test('getPendingCount returns correct count', () async {
      // Arrange
      final payload = {'data': 'test'};
      
      // Act & Assert - initially empty
      expect(await outboxRepo.getPendingCount(), 0);

      // Add items
      await outboxRepo.enqueue(
        eventId: 'event1',
        dedupeKey: 'key1',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      await outboxRepo.enqueue(
        eventId: 'event2',
        dedupeKey: 'key2',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      expect(await outboxRepo.getPendingCount(), 2);
    });

    test('getItemsByEventId returns items for specific event', () async {
      // Arrange
      final payload = {'data': 'test'};
      const targetEventId = 'target-event';

      await outboxRepo.enqueue(
        eventId: targetEventId,
        dedupeKey: 'key1',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      await outboxRepo.enqueue(
        eventId: 'other-event',
        dedupeKey: 'key2',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      // Act
      final targetItems = await outboxRepo.getItemsByEventId(targetEventId);

      // Assert
      expect(targetItems.length, 1);
      expect(targetItems[0].eventId, targetEventId);
    });

    test('deleteOldItems removes old items', () async {
      // Arrange
      final payload = {'data': 'test'};
      await outboxRepo.enqueue(
        eventId: 'event1',
        dedupeKey: 'key1',
        endpoint: '/api/test',
        method: 'POST',
        payload: payload,
      );

      // Act
      final deletedCount = await outboxRepo.deleteOldItems(const Duration(seconds: 1));
      
      // Wait longer to ensure item is definitely old
      await Future.delayed(const Duration(milliseconds: 1500));
      final deletedCountAfterDelay = await outboxRepo.deleteOldItems(const Duration(seconds: 1));

      // Assert
      expect(deletedCount, 0); // No old items initially
      expect(deletedCountAfterDelay, greaterThanOrEqualTo(1)); // At least one item should be deleted
    });
  });
}

// Helper to create test database
AppDatabase createTestDatabase() {
  return AppDatabase.withExecutor(NativeDatabase.memory());
}
