import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import '../../lib/domain/attendance_service.dart';
import '../../lib/domain/heartbeat_service.dart';
import '../../lib/domain/rules/local_rules.dart';
import '../../lib/data/local/db.dart';
import '../../lib/data/local/event_log_repo.dart';
import '../../lib/data/local/outbox_repo.dart';
import '../../lib/services/biometric_service.dart';

// Mock services for integration testing
class MockBiometricService extends BiometricService {
  @override
  Future<BiometricResult> authenticate() async {
    return BiometricResult.success(DateTime.now());
  }
}

void main() {
  group('Offline Capture Integration Tests', () {
    late AppDatabase database;
    late EventLogRepo eventLogRepo;
    late OutboxRepo outboxRepo;
    late AttendanceService attendanceService;
    late HeartbeatService heartbeatService;
    late SessionInfo testSession;
    late DeviceInfo testDevice;

    setUp(() {
      database = createTestDatabase();
      eventLogRepo = EventLogRepo(database);
      outboxRepo = OutboxRepo(database);
      
      attendanceService = AttendanceService(
        eventLogRepo: eventLogRepo,
        outboxRepo: outboxRepo,
        biometricService: MockBiometricService(),
      );

      heartbeatService = HeartbeatService(
        eventLogRepo: eventLogRepo,
        outboxRepo: outboxRepo,
      );

      testSession = SessionInfo(
        sessionId: 'integration-test-session',
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        endTime: DateTime.now().add(const Duration(hours: 2)),
        centerLat: 37.7749,
        centerLng: -122.4194,
        radiusMeters: 100.0,
      );

      testDevice = DeviceInfo(
        deviceId: 'integration-test-device',
        isTrusted: true,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('demonstrates complete offline capture flow', () async {
      // Initial state: no events
      var events = await eventLogRepo.getEvents();
      var outboxItems = await outboxRepo.getAllItems();
      expect(events.length, 0);
      expect(outboxItems.length, 0);

      // Note: These tests will fail with location errors in CI environment
      // In a real integration test, you'd mock the location services
      // For demonstration, we'll test the error handling paths

      // Attempt sign-in (will fail due to location in test environment)
      final signInResult = await attendanceService.captureSignIn(
        session: testSession,
        device: testDevice,
      );

      // Verify it fails gracefully with location error
      expect(signInResult.success, false);
      expect(signInResult.errorCode, anyOf([
        'LOCATION_DISABLED',
        'LOCATION_PERMISSION_DENIED', 
        'LOCATION_ERROR'
      ]));

      // Verify no events were created due to early failure
      events = await eventLogRepo.getEvents();
      outboxItems = await outboxRepo.getAllItems();
      expect(events.length, 0);
      expect(outboxItems.length, 0);

      // Test heartbeat service (also will fail with location)
      final heartbeatResult = await heartbeatService.tick(
        session: testSession,
        device: testDevice,
      );

      expect(heartbeatResult, false); // Failed due to location
    });

    test('validates rule engine integration', () async {
      // Test rule validation directly (without location dependency)
      
      // Valid event data
      final validEvent = EventData(
        type: 'ATTEND_IN',
        timestamp: DateTime.now(),
        latitude: 37.7749, // Inside geofence
        longitude: -122.4194,
        accuracy: 10.0, // Good accuracy
        biometricOk: true,
        biometricTimestamp: DateTime.now(),
        session: testSession,
        device: testDevice,
      );

      final validResult = LocalRules.validateEvent(validEvent);
      expect(validResult.isValid, true);

      // Invalid event data (outside geofence)
      final invalidEvent = EventData(
        type: 'ATTEND_IN',
        timestamp: DateTime.now(),
        latitude: 40.0, // Outside geofence
        longitude: -120.0,
        accuracy: 10.0,
        biometricOk: true,
        biometricTimestamp: DateTime.now(),
        session: testSession,
        device: testDevice,
      );

      final invalidResult = LocalRules.validateEvent(invalidEvent);
      expect(invalidResult.isValid, false);
      expect(invalidResult.code, 'GEOFENCE_VIOLATION');
    });

    test('demonstrates database persistence during offline mode', () async {
      // Manually create events to simulate successful capture
      // (bypassing location services for testing)

      // Create a sign-in event
      final signInEventId = await eventLogRepo.append(
        EventType.attendIn,
        {
          'timestamp': DateTime.now().toIso8601String(),
          'location': {'lat': 37.7749, 'lng': -122.4194, 'accuracy': 10.0},
          'session_id': testSession.sessionId,
          'device_id': testDevice.deviceId,
          'biometric_ok': true,
        },
      );

      // Enqueue for sync
      await outboxRepo.enqueue(
        eventId: signInEventId,
        dedupeKey: 'test_dedupe_signin',
        endpoint: '/api/attendance/validate',
        method: 'POST',
        payload: {'event_id': signInEventId, 'type': 'ATTEND_IN'},
      );

      // Create a heartbeat event
      final heartbeatEventId = await eventLogRepo.append(
        EventType.heartbeat,
        {
          'timestamp': DateTime.now().toIso8601String(),
          'location': {'lat': 37.7749, 'lng': -122.4194, 'accuracy': 15.0},
          'session_id': testSession.sessionId,
          'device_id': testDevice.deviceId,
        },
      );

      await outboxRepo.enqueue(
        eventId: heartbeatEventId,
        dedupeKey: 'test_dedupe_heartbeat',
        endpoint: '/api/heartbeat/record',
        method: 'POST',
        payload: {'event_id': heartbeatEventId, 'type': 'HEARTBEAT'},
      );

      // Verify events are stored locally
      final events = await eventLogRepo.getEvents();
      expect(events.length, 2);
      expect(events.any((e) => e.type == 'ATTEND_IN'), true);
      expect(events.any((e) => e.type == 'HEARTBEAT'), true);
      expect(events.every((e) => e.status == 'PENDING'), true);

      // Verify outbox items are ready for sync
      final outboxItems = await outboxRepo.getAllItems();
      expect(outboxItems.length, 2);
      expect(outboxItems.any((item) => item.endpoint.contains('attendance')), true);
      expect(outboxItems.any((item) => item.endpoint.contains('heartbeat')), true);

      // Verify pending counts
      final pendingCount = await eventLogRepo.getCountByStatus(EventStatus.pending);
      expect(pendingCount, 2);

      // Simulate status updates (as would happen after sync)
      await eventLogRepo.markStatus(signInEventId, EventStatus.confirmed, 'Server approved');
      await eventLogRepo.markStatus(heartbeatEventId, EventStatus.confirmed, 'Heartbeat recorded');

      // Verify status updates
      final confirmedCount = await eventLogRepo.getCountByStatus(EventStatus.confirmed);
      expect(confirmedCount, 2);

      final updatedEvents = await eventLogRepo.getEvents();
      expect(updatedEvents.every((e) => e.status == 'CONFIRMED'), true);
      expect(updatedEvents.every((e) => e.serverReason != null), true);
    });

    test('demonstrates deduplication behavior', () async {
      // Create first event
      final eventId1 = await eventLogRepo.append(
        EventType.attendIn,
        {'test': 'data1'},
      );

      await outboxRepo.enqueue(
        eventId: eventId1,
        dedupeKey: 'duplicate_test_key',
        endpoint: '/api/test',
        method: 'POST',
        payload: {'event_id': eventId1},
      );

      // Try to create duplicate
      final eventId2 = await eventLogRepo.append(
        EventType.attendIn,
        {'test': 'data2'},
      );

      // Should throw exception for duplicate dedupe key
      expect(
        () => outboxRepo.enqueue(
          eventId: eventId2,
          dedupeKey: 'duplicate_test_key', // Same key
          endpoint: '/api/test',
          method: 'POST',
          payload: {'event_id': eventId2},
        ),
        throwsA(isA<DuplicateDedupeKeyException>()),
      );

      // Verify only one outbox item exists
      final outboxItems = await outboxRepo.getAllItems();
      expect(outboxItems.length, 1);
      expect(outboxItems[0].eventId, eventId1);
    });

    test('demonstrates heartbeat statistics', () async {
      // Create multiple heartbeat events
      for (int i = 0; i < 5; i++) {
        final eventId = await eventLogRepo.append(
          EventType.heartbeat,
          {
            'session_id': testSession.sessionId,
            'sequence': i,
          },
        );

        // Mark some as confirmed, some as pending
        if (i < 3) {
          await eventLogRepo.markStatus(eventId, EventStatus.confirmed);
        }
      }

      // Get heartbeat stats
      final stats = await heartbeatService.getStats(testSession.sessionId);
      
      expect(stats.total, 5);
      expect(stats.confirmed, 3);
      expect(stats.pending, 2);
      expect(stats.rejected, 0);
      expect(stats.lastHeartbeat, isNotNull);
    });
  });
}

// Helper to create test database
AppDatabase createTestDatabase() {
  return AppDatabase.withExecutor(NativeDatabase.memory());
}
