import 'package:geolocator/geolocator.dart';
import '../data/local/event_log_repo.dart';
import '../data/local/outbox_repo.dart';
import '../services/logging_service.dart';
import '../services/metrics_service.dart';
import 'rules/local_rules.dart';

/// Service for generating periodic heartbeat events
class HeartbeatService {
  final EventLogRepo _eventLogRepo;
  final OutboxRepo _outboxRepo;
  
  static const String _component = 'HeartbeatService';

  HeartbeatService({
    required EventLogRepo eventLogRepo,
    required OutboxRepo outboxRepo,
  }) : _eventLogRepo = eventLogRepo,
       _outboxRepo = outboxRepo;

  /// Generate a heartbeat event
  Future<bool> tick({
    required SessionInfo session,
    required DeviceInfo device,
  }) async {
    logger.debug('Generating heartbeat', _component, {
      'session_id': session.sessionId,
      'device_id': device.deviceId,
    });

    try {
      // 1. Get current location (with relaxed requirements for heartbeat)
      final position = await _getCurrentLocationForHeartbeat();
      if (position == null) {
        logger.warn('Heartbeat skipped - no location', _component, {
          'session_id': session.sessionId,
        });
        return false;
      }

      // 2. Create event data (no biometric check for heartbeat)
      final eventData = EventData(
        type: EventType.heartbeat.value,
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        biometricOk: false, // Not required for heartbeat
        biometricTimestamp: null,
        session: session,
        device: device,
        lastEventType: null, // Sequence doesn't matter for heartbeat
      );

      // 3. Run basic validation (geofence, time window, device trust)
      final ruleResult = LocalRules.validateEvent(eventData);
      if (!ruleResult.isValid) {
        logger.warn('Heartbeat validation failed', _component, {
          'rule_code': ruleResult.code,
          'rule_message': ruleResult.message,
          'session_id': session.sessionId,
        });
        return false;
      }

      // 4. Create heartbeat payload
      final payload = {
        'timestamp': eventData.timestamp.toIso8601String(),
        'location': {
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
        },
        'session_id': session.sessionId,
        'device_id': device.deviceId,
        'heartbeat_sequence': DateTime.now().millisecondsSinceEpoch,
      };

      // 5. Append to event log
      final eventId = await _eventLogRepo.append(EventType.heartbeat, payload);

      // 6. Enqueue for sync
      final dedupeKey = _generateHeartbeatDedupeKey(eventData);
      await _outboxRepo.enqueue(
        eventId: eventId,
        dedupeKey: dedupeKey,
        endpoint: '/api/heartbeat/record',
        method: 'POST',
        payload: {
          'event_id': eventId,
          'type': EventType.heartbeat.value,
          'session_id': session.sessionId,
          'device_id': device.deviceId,
          'timestamp': eventData.timestamp.toIso8601String(),
          'location': {
            'lat': position.latitude,
            'lng': position.longitude,
            'accuracy': position.accuracy,
          },
        },
      );

      metrics.increment(MetricsService.captureHeartbeat);
      metrics.increment(MetricsService.captureSuccess);
      metrics.increment(MetricsService.outboxEnqueued);
      metrics.increment(MetricsService.eventPending);

      logger.info('Heartbeat generated successfully', _component, {
        'event_id': eventId,
        'dedupe_key': dedupeKey,
        'session_id': session.sessionId,
        'accuracy': position.accuracy,
      });

      return true;

    } catch (e) {
      metrics.increment(MetricsService.captureFailure);
      logger.error('Heartbeat generation failed', _component, {
        'error': e.toString(),
        'session_id': session.sessionId,
      });
      return false;
    }
  }

  /// Get current location for heartbeat (more lenient than attendance)
  Future<Position?> _getCurrentLocationForHeartbeat() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // Get current position with relaxed settings for heartbeat
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium, // Less strict than attendance
        timeLimit: const Duration(seconds: 5), // Shorter timeout
      );

      return position;

    } catch (e) {
      logger.debug('Failed to get heartbeat location', _component, {
        'error': e.toString(),
      });
      return null;
    }
  }

  /// Generate dedupe key for heartbeat (allows multiple per minute)
  String _generateHeartbeatDedupeKey(EventData eventData) {
    // Use session, device, and exact timestamp for heartbeat deduplication
    // This allows multiple heartbeats per minute but prevents exact duplicates
    return '${eventData.session.sessionId}_'
           '${eventData.device.deviceId}_'
           'HEARTBEAT_'
           '${eventData.timestamp.millisecondsSinceEpoch}';
  }

  /// Get heartbeat statistics for a session
  Future<HeartbeatStats> getStats(String sessionId) async {
    try {
      final events = await _eventLogRepo.getEvents();
      final heartbeats = events.where((e) => 
        e.type == EventType.heartbeat.value && 
        e.payload.contains(sessionId)
      ).toList();

      final pending = heartbeats.where((e) => e.status == EventStatus.pending.value).length;
      final confirmed = heartbeats.where((e) => e.status == EventStatus.confirmed.value).length;
      final rejected = heartbeats.where((e) => e.status == EventStatus.rejected.value).length;

      return HeartbeatStats(
        total: heartbeats.length,
        pending: pending,
        confirmed: confirmed,
        rejected: rejected,
        lastHeartbeat: heartbeats.isNotEmpty ? heartbeats.first.createdAt : null,
      );

    } catch (e) {
      logger.error('Failed to get heartbeat stats', _component, {
        'error': e.toString(),
        'session_id': sessionId,
      });

      return HeartbeatStats(
        total: 0,
        pending: 0,
        confirmed: 0,
        rejected: 0,
        lastHeartbeat: null,
      );
    }
  }
}

/// Heartbeat statistics
class HeartbeatStats {
  final int total;
  final int pending;
  final int confirmed;
  final int rejected;
  final DateTime? lastHeartbeat;

  HeartbeatStats({
    required this.total,
    required this.pending,
    required this.confirmed,
    required this.rejected,
    this.lastHeartbeat,
  });

  @override
  String toString() {
    return 'HeartbeatStats(total: $total, pending: $pending, confirmed: $confirmed, rejected: $rejected)';
  }
}
