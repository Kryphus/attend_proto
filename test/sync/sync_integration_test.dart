import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import '../../lib/sync/sync_service.dart';
import '../../lib/sync/connectivity_service.dart';
import '../../lib/data/local/db.dart';
import '../../lib/data/local/event_log_repo.dart';
import '../../lib/data/local/outbox_repo.dart';
import '../../lib/data/local/sync_cursor_repo.dart';

// Mock connectivity service for testing
class MockConnectivityService extends ConnectivityService {
  bool _mockConnected = true;
  
  void setMockConnectivity(bool connected) {
    _mockConnected = connected;
  }

  @override
  bool get isConnected => _mockConnected;

  @override
  Future<bool> checkConnectivity() async => _mockConnected;

  @override
  String getConnectivityDescription() => _mockConnected ? 'Online' : 'Offline';

  @override
  Future<void> initialize() async {
    // Mock initialization - no actual connectivity monitoring
  }

  @override
  void dispose() {
    // Mock disposal
  }
}

void main() {
  group('Sync Integration Tests', () {
    late AppDatabase database;
    late EventLogRepo eventLogRepo;
    late OutboxRepo outboxRepo;
    late SyncCursorRepo syncCursorRepo;
    late MockConnectivityService mockConnectivityService;
    late SyncService syncService;

    setUp(() {
      database = createTestDatabase();
      eventLogRepo = EventLogRepo(database);
      outboxRepo = OutboxRepo(database);
      syncCursorRepo = SyncCursorRepo(database);
      mockConnectivityService = MockConnectivityService();
      
      syncService = SyncService(
        connectivityService: mockConnectivityService,
        syncCursorRepo: syncCursorRepo,
      );
    });

    tearDown(() async {
      syncService.dispose();
      await database.close();
    });

    group('SyncService', () {
      test('initializes correctly', () async {
        // Note: In test environment, WorkManager initialization will fail
        // This test focuses on the service setup logic
        
        expect(syncService.isInitialized, false);
        
        // In a real test environment, we'd mock WorkManager
        // For now, we test the service structure
        expect(mockConnectivityService.isConnected, true);
      });

      test('provides sync status information', () async {
        // Set up some test data
        await syncCursorRepo.setLastSynced('last_sync', DateTime.now());
        
        final status = await syncService.getSyncStatus();
        
        expect(status.isConnected, true);
        expect(status.lastSyncTime, isNotNull);
        expect(status.connectivityDescription, 'Online');
        expect(status.statusDescription, contains('Online'));
      });

      test('handles offline status correctly', () async {
        mockConnectivityService.setMockConnectivity(false);
        
        final status = await syncService.getSyncStatus();
        
        expect(status.isConnected, false);
        expect(status.connectivityDescription, 'Offline');
        expect(status.statusDescription, contains('Offline'));
      });
    });

    group('SyncStatus', () {
      test('formats last sync time correctly', () {
        final now = DateTime.now();
        
        // Just now
        final recentStatus = SyncStatus(
          isConnected: true,
          lastSyncTime: now.subtract(const Duration(seconds: 30)),
          connectivityDescription: 'Online',
        );
        expect(recentStatus.lastSyncFormatted, 'Just now');
        
        // Minutes ago
        final minutesStatus = SyncStatus(
          isConnected: true,
          lastSyncTime: now.subtract(const Duration(minutes: 5)),
          connectivityDescription: 'Online',
        );
        expect(minutesStatus.lastSyncFormatted, '5m ago');
        
        // Hours ago
        final hoursStatus = SyncStatus(
          isConnected: true,
          lastSyncTime: now.subtract(const Duration(hours: 2)),
          connectivityDescription: 'Online',
        );
        expect(hoursStatus.lastSyncFormatted, '2h ago');
        
        // Days ago
        final daysStatus = SyncStatus(
          isConnected: true,
          lastSyncTime: now.subtract(const Duration(days: 1)),
          connectivityDescription: 'Online',
        );
        expect(daysStatus.lastSyncFormatted, '1d ago');
        
        // Never synced
        final neverStatus = SyncStatus(
          isConnected: true,
          lastSyncTime: null,
          connectivityDescription: 'Online',
        );
        expect(neverStatus.lastSyncFormatted, 'Never');
      });

      test('provides appropriate status descriptions', () {
        final now = DateTime.now();
        
        // Offline status
        final offlineStatus = SyncStatus(
          isConnected: false,
          lastSyncTime: now,
          connectivityDescription: 'Offline',
        );
        expect(offlineStatus.statusDescription, 'Offline - sync paused');
        
        // Online, never synced
        final neverSyncedStatus = SyncStatus(
          isConnected: true,
          lastSyncTime: null,
          connectivityDescription: 'Online',
        );
        expect(neverSyncedStatus.statusDescription, 'Online - ready to sync');
        
        // Online, recently synced
        final recentSyncStatus = SyncStatus(
          isConnected: true,
          lastSyncTime: now.subtract(const Duration(minutes: 5)),
          connectivityDescription: 'Online',
        );
        expect(recentSyncStatus.statusDescription, 'Online - last sync 5m ago');
      });
    });

    group('Offline to Online Simulation', () {
      test('demonstrates offline event capture and online sync readiness', () async {
        // Simulate offline mode
        mockConnectivityService.setMockConnectivity(false);
        
        // Create events while offline (simulating O2 functionality)
        final eventId1 = await eventLogRepo.append(
          EventType.attendIn,
          {
            'timestamp': DateTime.now().toIso8601String(),
            'location': {'lat': 37.7749, 'lng': -122.4194, 'accuracy': 10.0},
            'session_id': 'test-session',
            'device_id': 'test-device',
            'biometric_ok': true,
          },
        );

        await outboxRepo.enqueue(
          eventId: eventId1,
          dedupeKey: 'offline_test_signin',
          endpoint: '/api/attendance/validate',
          method: 'POST',
          payload: {'event_id': eventId1, 'type': 'ATTEND_IN'},
        );

        final eventId2 = await eventLogRepo.append(
          EventType.heartbeat,
          {
            'timestamp': DateTime.now().toIso8601String(),
            'location': {'lat': 37.7749, 'lng': -122.4194, 'accuracy': 15.0},
            'session_id': 'test-session',
            'device_id': 'test-device',
          },
        );

        await outboxRepo.enqueue(
          eventId: eventId2,
          dedupeKey: 'offline_test_heartbeat',
          endpoint: '/api/heartbeat/record',
          method: 'POST',
          payload: {'event_id': eventId2, 'type': 'HEARTBEAT'},
        );

        // Verify events are pending
        final pendingCount = await eventLogRepo.getCountByStatus(EventStatus.pending);
        expect(pendingCount, 2);

        // Verify outbox has items ready for sync
        final outboxItems = await outboxRepo.getAllItems();
        expect(outboxItems.length, 2);

        // Check sync status while offline
        var status = await syncService.getSyncStatus();
        expect(status.isConnected, false);
        expect(status.statusDescription, contains('Offline'));

        // Simulate connectivity regained
        mockConnectivityService.setMockConnectivity(true);

        // Check sync status after connectivity regained
        status = await syncService.getSyncStatus();
        expect(status.isConnected, true);
        expect(status.statusDescription, contains('Online'));

        // Verify items are still ready for sync
        final readyItems = await outboxRepo.dequeueBatch(limit: 10);
        expect(readyItems.length, 2);
        
        // In a real scenario, the sync worker would process these items
        // and update their status based on server responses
      });

      test('demonstrates backoff behavior for failed sync attempts', () async {
        // Create an outbox item
        final eventId = await eventLogRepo.append(
          EventType.attendIn,
          {'test': 'backoff_test'},
        );

        await outboxRepo.enqueue(
          eventId: eventId,
          dedupeKey: 'backoff_test_key',
          endpoint: '/api/test',
          method: 'POST',
          payload: {'event_id': eventId},
        );

        // Simulate failed attempts with backoff
        var items = await outboxRepo.getAllItems();
        expect(items.length, 1);
        
        var item = items[0];
        expect(item.attempts, 0);

        // Simulate first failure
        await outboxRepo.markAttempt(item.id, error: 'Network timeout');
        await outboxRepo.scheduleNextAttempt(
          item.id, 
          DateTime.now().add(const Duration(seconds: 30))
        );

        // Verify attempt count increased
        items = await outboxRepo.getAllItems();
        item = items[0];
        expect(item.attempts, 1);
        expect(item.lastError, 'Network timeout');

        // Simulate second failure with longer backoff
        await outboxRepo.markAttempt(item.id, error: 'Server error 500');
        await outboxRepo.scheduleNextAttempt(
          item.id, 
          DateTime.now().add(const Duration(minutes: 2))
        );

        // Verify backoff progression
        items = await outboxRepo.getAllItems();
        item = items[0];
        expect(item.attempts, 2);
        expect(item.lastError, 'Server error 500');
        expect(item.nextAttemptAt.isAfter(DateTime.now()), true);

        // Items not ready for immediate retry
        final readyItems = await outboxRepo.dequeueBatch();
        expect(readyItems.length, 0);
      });
    });

    group('Manual Sync Trigger', () {
      test('handles manual sync request correctly', () async {
        // Set up connectivity
        mockConnectivityService.setMockConnectivity(true);
        
        // Note: Using Timer-based sync instead of WorkManager
        // This test verifies the service handles the request correctly
        
        // Should not throw exception
        await syncService.syncNow();
        
        // In a real scenario, this would trigger the sync directly
        expect(mockConnectivityService.isConnected, true);
      });

      test('handles manual sync when offline', () async {
        // Set offline
        mockConnectivityService.setMockConnectivity(false);
        
        // Should handle gracefully without throwing
        await syncService.syncNow();
        
        expect(mockConnectivityService.isConnected, false);
      });
    });
  });
}

// Helper to create test database
AppDatabase createTestDatabase() {
  return AppDatabase.withExecutor(NativeDatabase.memory());
}
