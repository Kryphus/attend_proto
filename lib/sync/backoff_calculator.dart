import 'dart:math';
import '../config/feature_flags.dart';
import '../services/logging_service.dart';

/// Calculates backoff delays for retry operations
class BackoffCalculator {
  static const String _component = 'BackoffCalculator';
  static final Random _random = Random();

  /// Calculate next retry delay using jittered exponential backoff
  /// 
  /// Formula: min(maxRetryBackoff, baseDelay * (2^attempts)) + jitter
  /// Jitter: ±25% of calculated delay to avoid thundering herd
  static Duration calculateDelay({
    required int attempts,
    Duration baseDelay = const Duration(seconds: 30),
    Duration? maxDelay,
  }) {
    final maxRetryBackoff = maxDelay ?? FeatureFlags.maxRetryBackoff;
    
    // Exponential backoff: baseDelay * 2^attempts
    final exponentialDelay = baseDelay.inMilliseconds * pow(2, attempts).toInt();
    
    // Cap at maximum
    final cappedDelay = min(exponentialDelay, maxRetryBackoff.inMilliseconds);
    
    // Add jitter: ±25% of the delay
    final jitterRange = (cappedDelay * 0.25).toInt();
    final jitter = _random.nextInt(jitterRange * 2) - jitterRange;
    final finalDelay = max(1000, cappedDelay + jitter); // Minimum 1 second
    
    final result = Duration(milliseconds: finalDelay);
    
    logger.debug(
      'Backoff calculated',
      _component,
      {
        'attempts': attempts,
        'base_delay_ms': baseDelay.inMilliseconds,
        'exponential_delay_ms': exponentialDelay,
        'capped_delay_ms': cappedDelay,
        'jitter_ms': jitter,
        'final_delay_ms': finalDelay,
        'max_backoff_ms': maxRetryBackoff.inMilliseconds,
      },
    );
    
    return result;
  }

  /// Calculate next attempt time based on current attempts
  static DateTime calculateNextAttempt({
    required int attempts,
    DateTime? baseTime,
    Duration baseDelay = const Duration(seconds: 30),
    Duration? maxDelay,
  }) {
    final now = baseTime ?? DateTime.now();
    final delay = calculateDelay(
      attempts: attempts,
      baseDelay: baseDelay,
      maxDelay: maxDelay,
    );
    
    return now.add(delay);
  }

  /// Check if enough time has passed for a retry
  static bool shouldRetry(DateTime nextAttemptAt) {
    final now = DateTime.now();
    final shouldRetry = now.isAfter(nextAttemptAt) || now.isAtSameMomentAs(nextAttemptAt);
    
    if (!shouldRetry) {
      final waitTime = nextAttemptAt.difference(now);
      logger.debug(
        'Retry not ready',
        _component,
        {
          'next_attempt_at': nextAttemptAt.toIso8601String(),
          'current_time': now.toIso8601String(),
          'wait_time_ms': waitTime.inMilliseconds,
        },
      );
    }
    
    return shouldRetry;
  }

  /// Get human-readable delay description
  static String formatDelay(Duration delay) {
    if (delay.inHours > 0) {
      final hours = delay.inHours;
      final minutes = delay.inMinutes % 60;
      return '${hours}h ${minutes}m';
    } else if (delay.inMinutes > 0) {
      final minutes = delay.inMinutes;
      final seconds = delay.inSeconds % 60;
      return '${minutes}m ${seconds}s';
    } else {
      return '${delay.inSeconds}s';
    }
  }

  /// Reset backoff (for successful operations)
  static void logBackoffReset(String context) {
    logger.info(
      'Backoff reset after success',
      _component,
      {'context': context},
    );
  }

  /// Log backoff progression
  static void logBackoffProgression({
    required int attempts,
    required Duration delay,
    required String context,
    String? error,
  }) {
    logger.warn(
      'Backoff applied after failure',
      _component,
      {
        'context': context,
        'attempts': attempts,
        'delay_ms': delay.inMilliseconds,
        'delay_formatted': formatDelay(delay),
        'error': error,
      },
    );
  }
}
