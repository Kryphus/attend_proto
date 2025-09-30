import 'package:flutter_test/flutter_test.dart';
import '../../lib/sync/backoff_calculator.dart';
import '../../lib/config/feature_flags.dart';

void main() {
  group('BackoffCalculator', () {
    group('calculateDelay', () {
      test('returns base delay for first attempt (0 attempts)', () {
        const baseDelay = Duration(seconds: 30);
        final delay = BackoffCalculator.calculateDelay(
          attempts: 0,
          baseDelay: baseDelay,
        );

        // Should be base delay ± jitter (25%)
        expect(delay.inMilliseconds, greaterThanOrEqualTo(22500)); // 30s - 25%
        expect(delay.inMilliseconds, lessThanOrEqualTo(37500));    // 30s + 25%
      });

      test('applies exponential backoff correctly', () {
        const baseDelay = Duration(seconds: 10);
        
        // Attempt 1: 10s * 2^1 = 20s
        final delay1 = BackoffCalculator.calculateDelay(
          attempts: 1,
          baseDelay: baseDelay,
        );
        
        // Attempt 2: 10s * 2^2 = 40s
        final delay2 = BackoffCalculator.calculateDelay(
          attempts: 2,
          baseDelay: baseDelay,
        );
        
        // Attempt 3: 10s * 2^3 = 80s
        final delay3 = BackoffCalculator.calculateDelay(
          attempts: 3,
          baseDelay: baseDelay,
        );

        // Check exponential progression (accounting for jitter)
        expect(delay1.inMilliseconds, greaterThan(15000)); // ~20s - jitter
        expect(delay1.inMilliseconds, lessThan(25000));    // ~20s + jitter
        
        expect(delay2.inMilliseconds, greaterThan(30000)); // ~40s - jitter
        expect(delay2.inMilliseconds, lessThan(50000));    // ~40s + jitter
        
        expect(delay3.inMilliseconds, greaterThan(60000)); // ~80s - jitter
        expect(delay3.inMilliseconds, lessThan(100000));   // ~80s + jitter
      });

      test('respects maximum delay cap', () {
        const baseDelay = Duration(seconds: 30);
        const maxDelay = Duration(minutes: 5); // 5 minutes
        
        // High attempt count that would exceed max without cap
        final delay = BackoffCalculator.calculateDelay(
          attempts: 10, // Would be 30s * 2^10 = ~8.5 hours without cap
          baseDelay: baseDelay,
          maxDelay: maxDelay,
        );

        // Should be capped at max delay ± jitter
        expect(delay.inMilliseconds, lessThanOrEqualTo(375000)); // 5min + 25%
        expect(delay.inMilliseconds, greaterThanOrEqualTo(225000)); // 5min - 25%
      });

      test('uses FeatureFlags.maxRetryBackoff as default max', () {
        const baseDelay = Duration(seconds: 30);
        
        final delay = BackoffCalculator.calculateDelay(
          attempts: 20, // Very high attempt count
          baseDelay: baseDelay,
        );

        // Should be capped at FeatureFlags.maxRetryBackoff
        final maxAllowed = FeatureFlags.maxRetryBackoff.inMilliseconds;
        final maxWithJitter = (maxAllowed * 1.25).toInt();
        
        expect(delay.inMilliseconds, lessThanOrEqualTo(maxWithJitter));
      });

      test('enforces minimum delay of 1 second', () {
        const baseDelay = Duration(milliseconds: 100); // Very small base
        
        final delay = BackoffCalculator.calculateDelay(
          attempts: 0,
          baseDelay: baseDelay,
        );

        expect(delay.inMilliseconds, greaterThanOrEqualTo(1000));
      });

      test('applies jitter consistently', () {
        const baseDelay = Duration(seconds: 60);
        final delays = <Duration>[];
        
        // Generate multiple delays with same parameters
        for (int i = 0; i < 10; i++) {
          delays.add(BackoffCalculator.calculateDelay(
            attempts: 2,
            baseDelay: baseDelay,
          ));
        }

        // All delays should be different due to jitter
        final uniqueDelays = delays.toSet();
        expect(uniqueDelays.length, greaterThan(1));
        
        // All should be within expected range (60s * 2^2 = 240s ± 25%)
        for (final delay in delays) {
          expect(delay.inMilliseconds, greaterThanOrEqualTo(180000)); // 240s - 25%
          expect(delay.inMilliseconds, lessThanOrEqualTo(300000));    // 240s + 25%
        }
      });
    });

    group('calculateNextAttempt', () {
      test('calculates correct next attempt time', () {
        final baseTime = DateTime(2024, 1, 1, 12, 0, 0);
        const baseDelay = Duration(minutes: 5);
        
        final nextAttempt = BackoffCalculator.calculateNextAttempt(
          attempts: 1,
          baseTime: baseTime,
          baseDelay: baseDelay,
        );

        // Should be baseTime + calculated delay
        final expectedMinTime = baseTime.add(const Duration(minutes: 7, seconds: 30)); // 5min * 2 - 25%
        final expectedMaxTime = baseTime.add(const Duration(minutes: 12, seconds: 30)); // 5min * 2 + 25%
        
        expect(nextAttempt.isAfter(expectedMinTime), true);
        expect(nextAttempt.isBefore(expectedMaxTime), true);
      });

      test('uses current time when baseTime is null', () {
        final beforeCall = DateTime.now();
        
        final nextAttempt = BackoffCalculator.calculateNextAttempt(
          attempts: 0,
          baseDelay: const Duration(seconds: 30),
        );
        
        final afterCall = DateTime.now();
        
        // Next attempt should be after current time
        expect(nextAttempt.isAfter(beforeCall), true);
        expect(nextAttempt.isBefore(afterCall.add(const Duration(minutes: 2))), true);
      });
    });

    group('shouldRetry', () {
      test('returns true when next attempt time has passed', () {
        final pastTime = DateTime.now().subtract(const Duration(minutes: 1));
        expect(BackoffCalculator.shouldRetry(pastTime), true);
      });

      test('returns true when next attempt time is now', () {
        final now = DateTime.now();
        expect(BackoffCalculator.shouldRetry(now), true);
      });

      test('returns false when next attempt time is in future', () {
        final futureTime = DateTime.now().add(const Duration(minutes: 1));
        expect(BackoffCalculator.shouldRetry(futureTime), false);
      });
    });

    group('formatDelay', () {
      test('formats seconds correctly', () {
        expect(BackoffCalculator.formatDelay(const Duration(seconds: 30)), '30s');
        expect(BackoffCalculator.formatDelay(const Duration(seconds: 5)), '5s');
      });

      test('formats minutes and seconds correctly', () {
        expect(BackoffCalculator.formatDelay(const Duration(minutes: 2, seconds: 30)), '2m 30s');
        expect(BackoffCalculator.formatDelay(const Duration(minutes: 1)), '1m 0s');
      });

      test('formats hours and minutes correctly', () {
        expect(BackoffCalculator.formatDelay(const Duration(hours: 1, minutes: 30)), '1h 30m');
        expect(BackoffCalculator.formatDelay(const Duration(hours: 2)), '2h 0m');
      });

      test('prioritizes largest unit', () {
        expect(BackoffCalculator.formatDelay(const Duration(hours: 1, minutes: 30, seconds: 45)), '1h 30m');
        expect(BackoffCalculator.formatDelay(const Duration(minutes: 5, seconds: 30)), '5m 30s');
      });
    });

    group('backoff progression', () {
      test('demonstrates realistic backoff sequence', () {
        const baseDelay = Duration(seconds: 30);
        final delays = <Duration>[];
        
        // Simulate first 5 retry attempts
        for (int attempt = 0; attempt < 5; attempt++) {
          delays.add(BackoffCalculator.calculateDelay(
            attempts: attempt,
            baseDelay: baseDelay,
          ));
        }

        // Verify progression (accounting for jitter)
        expect(delays[0].inSeconds, lessThan(60));     // ~30s
        expect(delays[1].inSeconds, lessThan(120));    // ~60s
        expect(delays[2].inSeconds, lessThan(240));    // ~120s
        expect(delays[3].inSeconds, lessThan(480));    // ~240s
        expect(delays[4].inSeconds, lessThan(960));    // ~480s
        
        // Each delay should generally be larger than the previous (with jitter variance)
        // We'll check that the average is increasing
        final avg1 = delays.take(2).map((d) => d.inSeconds).reduce((a, b) => a + b) / 2;
        final avg2 = delays.skip(2).take(2).map((d) => d.inSeconds).reduce((a, b) => a + b) / 2;
        
        expect(avg2, greaterThan(avg1));
      });
    });
  });
}
