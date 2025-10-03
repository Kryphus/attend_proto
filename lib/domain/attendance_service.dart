import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../data/local/event_log_repo.dart';
import '../data/local/outbox_repo.dart';
import '../services/biometric_service.dart';
import '../services/logging_service.dart';
import '../services/metrics_service.dart';
import 'rules/local_rules.dart';

/// Result of an attendance capture operation
class CaptureResult {
  final bool success;
  final String? eventId;
  final String? errorCode;
  final String? errorMessage;

  const CaptureResult.success(this.eventId) 
      : success = true, errorCode = null, errorMessage = null;
  
  const CaptureResult.failure(this.errorCode, this.errorMessage) 
      : success = false, eventId = null;

  @override
  String toString() => success 
      ? 'SUCCESS(eventId: $eventId)' 
      : 'FAILURE($errorCode: $errorMessage)';
}

/// Service for capturing attendance events (sign-in/out)
class AttendanceService {
  final EventLogRepo _eventLogRepo;
  final OutboxRepo _outboxRepo;
  final BiometricService _biometricService;
  final Uuid _uuid = const Uuid();
  
  static const String _component = 'AttendanceService';

  AttendanceService({
    required EventLogRepo eventLogRepo,
    required OutboxRepo outboxRepo,
    required BiometricService biometricService,
  }) : _eventLogRepo = eventLogRepo,
       _outboxRepo = outboxRepo,
       _biometricService = biometricService;

  /// Capture a sign-in event
  Future<CaptureResult> captureSignIn({
    required SessionInfo session,
    required DeviceInfo device,
    String? lastEventType,
  }) async {
    logger.info('Starting sign-in capture', _component, {
      'session_id': session.sessionId,
      'device_id': device.deviceId,
    });

    metrics.increment(MetricsService.captureSignIn);
    final result = await _captureEvent(
      type: EventType.attendIn,
      session: session,
      device: device,
      lastEventType: lastEventType,
    );
    
    if (result.success) {
      metrics.increment(MetricsService.captureSuccess);
    } else {
      metrics.increment(MetricsService.captureFailure);
    }
    
    return result;
  }

  /// Capture a sign-out event
  Future<CaptureResult> captureSignOut({
    required SessionInfo session,
    required DeviceInfo device,
    String? lastEventType,
  }) async {
    logger.info('Starting sign-out capture', _component, {
      'session_id': session.sessionId,
      'device_id': device.deviceId,
    });

    metrics.increment(MetricsService.captureSignOut);
    final result = await _captureEvent(
      type: EventType.attendOut,
      session: session,
      device: device,
      lastEventType: lastEventType,
    );
    
    if (result.success) {
      metrics.increment(MetricsService.captureSuccess);
    } else {
      metrics.increment(MetricsService.captureFailure);
    }
    
    return result;
  }

  /// Internal method to capture any attendance event
  Future<CaptureResult> _captureEvent({
    required EventType type,
    required SessionInfo session,
    required DeviceInfo device,
    String? lastEventType,
  }) async {
    try {
      // 1. Get current location
      final locationResult = await _getCurrentLocation();
      if (!locationResult.success) {
        return CaptureResult.failure(
          locationResult.errorCode!,
          locationResult.errorMessage!,
        );
      }

      final position = locationResult.position!;

      // 2. Check biometric authentication
      final biometricResult = await _checkBiometric();
      if (!biometricResult.success) {
        return CaptureResult.failure(
          biometricResult.errorCode!,
          biometricResult.errorMessage!,
        );
      }

      // 3. Create event data for validation
      final eventData = EventData(
        type: type.value,
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        biometricOk: biometricResult.authenticated!,
        biometricTimestamp: biometricResult.timestamp,
        session: session,
        device: device,
        lastEventType: lastEventType,
      );

      // 4. Run local validation rules
      final ruleResult = LocalRules.validateEvent(eventData);
      if (!ruleResult.isValid) {
        logger.warn('Event validation failed', _component, {
          'rule_code': ruleResult.code,
          'rule_message': ruleResult.message,
          'event_type': type.value,
        });

        metrics.increment(MetricsService.ruleViolation);
        return CaptureResult.failure(ruleResult.code!, ruleResult.message!);
      }

      metrics.increment(MetricsService.rulePass);

      // 5. Create event payload
      final payload = _createEventPayload(eventData);

      // 6. Append to event log
      final eventId = await _eventLogRepo.append(type, payload);

      // 7. Enqueue for sync
      final dedupeKey = _generateDedupeKey(eventData);
      await _outboxRepo.enqueue(
        eventId: eventId,
        dedupeKey: dedupeKey,
        endpoint: '/api/attendance/validate',
        method: 'POST',
        payload: {
          'event_id': eventId,
          'type': type.value,
          'session_id': session.sessionId,
          'device_id': device.deviceId,
          'timestamp': eventData.timestamp.toIso8601String(),
          'location': {
            'lat': position.latitude,
            'lng': position.longitude,
            'accuracy': position.accuracy,
          },
          'biometric_ok': biometricResult.authenticated,
          'biometric_timestamp': biometricResult.timestamp?.toIso8601String(),
        },
      );

      metrics.increment(MetricsService.outboxEnqueued);
      metrics.increment(MetricsService.eventPending);

      logger.info('Event captured successfully', _component, {
        'event_id': eventId,
        'event_type': type.value,
        'dedupe_key': dedupeKey,
        'session_id': session.sessionId,
      });

      return CaptureResult.success(eventId);

    } catch (e) {
      logger.error('Event capture failed', _component, {
        'error': e.toString(),
        'event_type': type.value,
      });

      return CaptureResult.failure('CAPTURE_ERROR', 'Failed to capture event: $e');
    }
  }

  /// Get current location with error handling
  Future<_LocationResult> _getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const _LocationResult.failure(
          'LOCATION_DISABLED',
          'Location services are disabled',
        );
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const _LocationResult.failure(
            'LOCATION_PERMISSION_DENIED',
            'Location permissions are denied',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const _LocationResult.failure(
          'LOCATION_PERMISSION_DENIED_FOREVER',
          'Location permissions are permanently denied',
        );
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return _LocationResult.success(position);

    } catch (e) {
      return _LocationResult.failure(
        'LOCATION_ERROR',
        'Failed to get location: $e',
      );
    }
  }

  /// Check biometric authentication
  Future<_BiometricResult> _checkBiometric() async {
    try {
      final result = await _biometricService.authenticate();
      return _BiometricResult.success(result.success, result.timestamp);
    } catch (e) {
      return _BiometricResult.failure(
        'BIOMETRIC_ERROR',
        'Biometric authentication failed: $e',
      );
    }
  }

  /// Create event payload for storage
  Map<String, dynamic> _createEventPayload(EventData eventData) {
    return {
      'timestamp': eventData.timestamp.toIso8601String(),
      'location': {
        'lat': eventData.latitude,
        'lng': eventData.longitude,
        'accuracy': eventData.accuracy,
      },
      'session_id': eventData.session.sessionId,
      'device_id': eventData.device.deviceId,
      'biometric_ok': eventData.biometricOk,
      'biometric_timestamp': eventData.biometricTimestamp?.toIso8601String(),
    };
  }

  /// Generate unique dedupe key for the event
  String _generateDedupeKey(EventData eventData) {
    // Use session, device, type, and timestamp (rounded to minute) for deduplication
    final minuteTimestamp = DateTime(
      eventData.timestamp.year,
      eventData.timestamp.month,
      eventData.timestamp.day,
      eventData.timestamp.hour,
      eventData.timestamp.minute,
    );

    return '${eventData.session.sessionId}_'
           '${eventData.device.deviceId}_'
           '${eventData.type}_'
           '${minuteTimestamp.millisecondsSinceEpoch}';
  }
}

/// Internal result classes
class _LocationResult {
  final bool success;
  final Position? position;
  final String? errorCode;
  final String? errorMessage;

  const _LocationResult.success(this.position) 
      : success = true, errorCode = null, errorMessage = null;
  
  const _LocationResult.failure(this.errorCode, this.errorMessage) 
      : success = false, position = null;
}

class _BiometricResult {
  final bool success;
  final bool? authenticated;
  final DateTime? timestamp;
  final String? errorCode;
  final String? errorMessage;

  const _BiometricResult.success(this.authenticated, this.timestamp) 
      : success = true, errorCode = null, errorMessage = null;
  
  const _BiometricResult.failure(this.errorCode, this.errorMessage) 
      : success = false, authenticated = null, timestamp = null;
}
