import 'package:geolocator/geolocator.dart';
import '../../config/feature_flags.dart';
import '../../services/logging_service.dart';
import '../../utils/distance.dart';

/// Result of a rule validation
class RuleResult {
  final bool isValid;
  final String? code;
  final String? message;

  const RuleResult.valid() : isValid = true, code = null, message = null;
  const RuleResult.invalid(this.code, this.message) : isValid = false;

  @override
  String toString() => isValid ? 'VALID' : 'INVALID($code: $message)';
}

/// Session information for validation
class SessionInfo {
  final String sessionId;
  final DateTime startTime;
  final DateTime endTime;
  final double centerLat;
  final double centerLng;
  final double radiusMeters;

  SessionInfo({
    required this.sessionId,
    required this.startTime,
    required this.endTime,
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
  });
}

/// Device information for validation
class DeviceInfo {
  final String deviceId;
  final bool isTrusted;

  DeviceInfo({
    required this.deviceId,
    required this.isTrusted,
  });
}

/// Event data for validation
class EventData {
  final String type; // 'ATTEND_IN', 'ATTEND_OUT', 'HEARTBEAT'
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double accuracy;
  final bool biometricOk;
  final DateTime? biometricTimestamp;
  final SessionInfo session;
  final DeviceInfo device;
  final String? lastEventType; // For duplicate prevention

  EventData({
    required this.type,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.biometricOk,
    this.biometricTimestamp,
    required this.session,
    required this.device,
    this.lastEventType,
  });
}

/// Local validation rules engine
class LocalRules {
  static const String _component = 'LocalRules';

  /// Validate all rules for an event
  static RuleResult validateEvent(EventData event) {
    final rules = [
      () => _validateGeofence(event),
      () => _validateTimeWindow(event),
      () => _validateAccuracy(event),
      () => _validateBiometricFreshness(event),
      () => _validateSequence(event),
      () => _validateTrustedDevice(event),
    ];

    for (final rule in rules) {
      final result = rule();
      if (!result.isValid) {
        logger.warn(
          'Rule validation failed',
          _component,
          {
            'rule_code': result.code,
            'rule_message': result.message,
            'event_type': event.type,
            'session_id': event.session.sessionId,
          },
        );
        return result;
      }
    }

    logger.info(
      'All rules passed',
      _component,
      {
        'event_type': event.type,
        'session_id': event.session.sessionId,
        'device_id': event.device.deviceId,
      },
    );

    return const RuleResult.valid();
  }

  /// Rule 1: Check if location is within geofence
  static RuleResult _validateGeofence(EventData event) {
    final distance = DistanceUtils.getDistance(
      lat1: event.latitude,
      lng1: event.longitude,
      lat2: event.session.centerLat,
      lng2: event.session.centerLng,
    );

    // Check for error in distance calculation
    if (distance < 0) {
      return RuleResult.invalid(
        'LOCATION_ERROR',
        'Unable to calculate distance to geofence center',
      );
    }

    if (distance > event.session.radiusMeters) {
      return RuleResult.invalid(
        'GEOFENCE_VIOLATION',
        'Location is ${distance.toStringAsFixed(1)}m from center, '
        'exceeds ${event.session.radiusMeters.toStringAsFixed(1)}m radius',
      );
    }

    return const RuleResult.valid();
  }

  /// Rule 2: Check if event is within session time window
  static RuleResult _validateTimeWindow(EventData event) {
    final now = event.timestamp;

    if (now.isBefore(event.session.startTime)) {
      return RuleResult.invalid(
        'SESSION_NOT_STARTED',
        'Event at ${_formatTime(now)} is before session start ${_formatTime(event.session.startTime)}',
      );
    }

    if (now.isAfter(event.session.endTime)) {
      return RuleResult.invalid(
        'SESSION_ENDED',
        'Event at ${_formatTime(now)} is after session end ${_formatTime(event.session.endTime)}',
      );
    }

    return const RuleResult.valid();
  }

  /// Rule 3: Check if location accuracy is acceptable
  static RuleResult _validateAccuracy(EventData event) {
    const maxAccuracy = 50.0; // meters - could be made configurable

    if (event.accuracy > maxAccuracy) {
      return RuleResult.invalid(
        'POOR_ACCURACY',
        'Location accuracy ${event.accuracy.toStringAsFixed(1)}m exceeds ${maxAccuracy}m threshold',
      );
    }

    return const RuleResult.valid();
  }

  /// Rule 4: Check biometric freshness for sign-in/out events
  static RuleResult _validateBiometricFreshness(EventData event) {
    // Only check biometrics for sign-in/out, not heartbeat
    if (event.type == 'HEARTBEAT') {
      return const RuleResult.valid();
    }

    if (!event.biometricOk) {
      return RuleResult.invalid(
        'BIOMETRIC_REQUIRED',
        'Biometric authentication required for ${event.type}',
      );
    }

    if (event.biometricTimestamp == null) {
      return RuleResult.invalid(
        'BIOMETRIC_TIMESTAMP_MISSING',
        'Biometric timestamp required for validation',
      );
    }

    final age = event.timestamp.difference(event.biometricTimestamp!);
    if (age > FeatureFlags.biometricFreshness) {
      return RuleResult.invalid(
        'BIOMETRIC_STALE',
        'Biometric authentication is ${_formatDuration(age)} old, '
        'exceeds ${_formatDuration(FeatureFlags.biometricFreshness)} limit',
      );
    }

    return const RuleResult.valid();
  }

  /// Rule 5: Check for duplicate/invalid sequence (no double sign-in/out)
  static RuleResult _validateSequence(EventData event) {
    // Skip sequence check for heartbeat
    if (event.type == 'HEARTBEAT') {
      return const RuleResult.valid();
    }

    final lastEvent = event.lastEventType;
    
    // First event is always valid
    if (lastEvent == null) {
      return const RuleResult.valid();
    }

    // Check for invalid sequences
    if (event.type == 'ATTEND_IN' && lastEvent == 'ATTEND_IN') {
      return const RuleResult.invalid(
        'DUPLICATE_SIGN_IN',
        'Cannot sign in twice without signing out first',
      );
    }

    if (event.type == 'ATTEND_OUT' && lastEvent == 'ATTEND_OUT') {
      return const RuleResult.invalid(
        'DUPLICATE_SIGN_OUT',
        'Cannot sign out twice without signing in first',
      );
    }

    if (event.type == 'ATTEND_OUT' && lastEvent != 'ATTEND_IN') {
      return const RuleResult.invalid(
        'SIGN_OUT_WITHOUT_SIGN_IN',
        'Cannot sign out without signing in first',
      );
    }

    return const RuleResult.valid();
  }

  /// Rule 6: Check if device is trusted
  static RuleResult _validateTrustedDevice(EventData event) {
    if (!event.device.isTrusted) {
      return RuleResult.invalid(
        'UNTRUSTED_DEVICE',
        'Device ${event.device.deviceId} is not registered as trusted',
      );
    }

    return const RuleResult.valid();
  }

  // Helper methods
  static String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }

  static String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}
