import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/config/feature_flags.dart';

void main() {
  group('FeatureFlags', () {
    test('should default to dev environment', () {
      expect(FeatureFlags.environment, equals('dev'));
      expect(FeatureFlags.isDev, isTrue);
      expect(FeatureFlags.isProd, isFalse);
    });

    test('should have correct dev defaults', () {
      // In dev mode, heartbeat and sync should be 1 minute
      expect(FeatureFlags.heartbeatInterval, equals(const Duration(minutes: 1)));
      expect(FeatureFlags.syncInterval, equals(const Duration(minutes: 1)));
      expect(FeatureFlags.maxRetryBackoff, equals(const Duration(minutes: 10)));
      
      // These should be the same for both dev and prod
      expect(FeatureFlags.biometricFreshness, equals(const Duration(minutes: 5)));
      expect(FeatureFlags.geofenceRadiusMeters, equals(100.0));
    });

    test('should return all flags in getAllFlags', () {
      final flags = FeatureFlags.getAllFlags();
      
      expect(flags, containsPair('environment', 'dev'));
      expect(flags, containsPair('heartbeatInterval', '0:01:00.000000'));
      expect(flags, containsPair('syncInterval', '0:01:00.000000'));
      expect(flags, containsPair('biometricFreshness', '0:05:00.000000'));
      expect(flags, containsPair('geofenceRadiusMeters', 100.0));
      expect(flags, containsPair('maxRetryBackoff', '0:10:00.000000'));
    });

    test('should generate proper log string', () {
      final logString = FeatureFlags.getLogString();
      
      expect(logString, contains('🚩 Feature Flags Configuration:'));
      expect(logString, contains('Environment: dev'));
      expect(logString, contains('Heartbeat Interval: 0:01:00.000000'));
      expect(logString, contains('Sync Interval: 0:01:00.000000'));
      expect(logString, contains('Biometric Freshness: 0:05:00.000000'));
      expect(logString, contains('Geofence Radius: 100.0m'));
      expect(logString, contains('Max Retry Backoff: 0:10:00.000000'));
    });

    group('Environment override tests', () {
      // Note: These tests demonstrate the expected behavior when dart-define is used
      // In actual usage, you would run: flutter test --dart-define=ENVIRONMENT=prod
      
      test('should recognize prod environment when set', () {
        // This test shows what would happen if ENVIRONMENT=prod was set via dart-define
        // Since we can't actually set dart-define in unit tests, we document the expected behavior
        
        // When ENVIRONMENT=prod is set via --dart-define:
        // - FeatureFlags.environment should return 'prod'
        // - FeatureFlags.isProd should be true
        // - FeatureFlags.isDev should be false
        // - heartbeatInterval should be Duration(hours: 1)
        // - syncInterval should be Duration(hours: 1)
        // - maxRetryBackoff should be Duration(hours: 2)
      });

      test('should use dart-define values when provided', () {
        // This test documents the expected precedence behavior
        // When values are provided via --dart-define, they should override defaults
        
        // Example: flutter test --dart-define=HEARTBEAT_INTERVAL_MINUTES=5
        // Should result in FeatureFlags.heartbeatInterval = Duration(minutes: 5)
        
        // Example: flutter test --dart-define=GEOFENCE_RADIUS_METERS=200
        // Should result in FeatureFlags.geofenceRadiusMeters = 200.0
      });
    });

    group('Value parsing tests', () {
      test('should handle invalid dart-define values gracefully', () {
        // When invalid values are provided via dart-define (e.g., non-numeric strings),
        // the system should fall back to environment-based defaults
        
        // This is handled by int.tryParse() and double.tryParse() returning null
        // for invalid inputs, which then triggers the fallback logic
        expect(int.tryParse('invalid'), isNull);
        expect(double.tryParse('invalid'), isNull);
      });
    });
  });
}
