import 'package:flutter_test/flutter_test.dart';
import '../../../lib/domain/rules/local_rules.dart';
import '../../../lib/config/feature_flags.dart';

void main() {
  group('LocalRules', () {
    late SessionInfo testSession;
    late DeviceInfo testDevice;

    setUp(() {
      testSession = SessionInfo(
        sessionId: 'test-session',
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        endTime: DateTime.now().add(const Duration(hours: 2)),
        centerLat: 37.7749,
        centerLng: -122.4194,
        radiusMeters: 100.0,
      );

      testDevice = DeviceInfo(
        deviceId: 'test-device',
        isTrusted: true,
      );
    });

    group('Geofence Validation', () {
      test('passes when inside geofence', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749, // Same as center
          longitude: -122.4194, // Same as center
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });

      test('fails when outside geofence', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.8049, // ~3km away
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'GEOFENCE_VIOLATION');
        expect(result.message, contains('exceeds'));
      });

      test('passes when close to radius boundary', () {
        // Use a point that's definitely within 100m radius
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7757, // ~90m north (within radius)
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });
    });

    group('Time Window Validation', () {
      test('passes when within session time', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(), // Current time should be within session
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });

      test('fails when before session start', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: testSession.startTime.subtract(const Duration(minutes: 1)),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'SESSION_NOT_STARTED');
      });

      test('fails when after session end', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: testSession.endTime.add(const Duration(minutes: 1)),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'SESSION_ENDED');
      });
    });

    group('Accuracy Validation', () {
      test('passes with good accuracy', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0, // Good accuracy
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });

      test('fails with poor accuracy', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 100.0, // Poor accuracy
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'POOR_ACCURACY');
        expect(result.message, contains('100.0m exceeds 50.0m'));
      });
    });

    group('Biometric Freshness Validation', () {
      test('passes for heartbeat without biometric', () {
        final event = EventData(
          type: 'HEARTBEAT',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: false, // No biometric for heartbeat
          biometricTimestamp: null,
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });

      test('passes with fresh biometric for attendance', () {
        final now = DateTime.now();
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: now,
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: now.subtract(const Duration(minutes: 1)), // Fresh
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });

      test('fails with stale biometric', () {
        final now = DateTime.now();
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: now,
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: now.subtract(const Duration(minutes: 10)), // Stale
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'BIOMETRIC_STALE');
      });

      test('fails without biometric for attendance', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: false, // No biometric
          biometricTimestamp: null,
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'BIOMETRIC_REQUIRED');
      });

      test('fails with missing biometric timestamp', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: null, // Missing timestamp
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'BIOMETRIC_TIMESTAMP_MISSING');
      });
    });

    group('Sequence Validation', () {
      test('allows first sign-in', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
          lastEventType: null, // First event
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });

      test('allows sign-out after sign-in', () {
        final event = EventData(
          type: 'ATTEND_OUT',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
          lastEventType: 'ATTEND_IN',
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });

      test('prevents double sign-in', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
          lastEventType: 'ATTEND_IN', // Already signed in
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'DUPLICATE_SIGN_IN');
      });

      test('prevents double sign-out', () {
        final event = EventData(
          type: 'ATTEND_OUT',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
          lastEventType: 'ATTEND_OUT', // Already signed out
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'DUPLICATE_SIGN_OUT');
      });

      test('prevents sign-out without sign-in', () {
        final event = EventData(
          type: 'ATTEND_OUT',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
          lastEventType: 'HEARTBEAT', // Last was heartbeat, not sign-in
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'SIGN_OUT_WITHOUT_SIGN_IN');
      });

      test('allows heartbeat regardless of sequence', () {
        final event = EventData(
          type: 'HEARTBEAT',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: false,
          biometricTimestamp: null,
          session: testSession,
          device: testDevice,
          lastEventType: 'ATTEND_OUT', // Any last event is fine for heartbeat
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });
    });

    group('Device Trust Validation', () {
      test('passes with trusted device', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice, // Trusted device
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
      });

      test('fails with untrusted device', () {
        final untrustedDevice = DeviceInfo(
          deviceId: 'untrusted-device',
          isTrusted: false,
        );

        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: untrustedDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        expect(result.code, 'UNTRUSTED_DEVICE');
        expect(result.message, contains('untrusted-device'));
      });
    });

    group('Combined Rule Validation', () {
      test('fails on first invalid rule encountered', () {
        // Create event that fails multiple rules
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 40.0, // Outside geofence
          longitude: -120.0, // Outside geofence
          accuracy: 100.0, // Poor accuracy
          biometricOk: false, // No biometric
          biometricTimestamp: null,
          session: testSession,
          device: DeviceInfo(deviceId: 'bad-device', isTrusted: false), // Untrusted
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, false);
        // Should fail on geofence first (rules are checked in order)
        expect(result.code, 'GEOFENCE_VIOLATION');
      });

      test('passes when all rules are satisfied', () {
        final event = EventData(
          type: 'ATTEND_IN',
          timestamp: DateTime.now(),
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 10.0,
          biometricOk: true,
          biometricTimestamp: DateTime.now(),
          session: testSession,
          device: testDevice,
        );

        final result = LocalRules.validateEvent(event);
        expect(result.isValid, true);
        expect(result.code, null);
        expect(result.message, null);
      });
    });
  });
}
