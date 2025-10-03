import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/logging_service.dart';
import '../../services/metrics_service.dart';

/// API client for Supabase backend communication
class ApiClient {
  static const String _component = 'ApiClient';
  
  final SupabaseClient _supabase;
  
  // Test IDs from the SQL setup
  static const String testUserId = '550e8400-e29b-41d4-a716-446655440000';
  static const String testDeviceId = '550e8400-e29b-41d4-a716-446655440001';
  static const String testSessionId = '550e8400-e29b-41d4-a716-446655440002';

  ApiClient(this._supabase);

  /// Post attendance event (sign-in/sign-out) to server
  Future<ApiResponse> postAttendance({
    required String eventId,
    required String eventType, // 'ATTEND_IN' or 'ATTEND_OUT'
    required String dedupeKey,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool biometricOk,
    DateTime? biometricTimestamp,
  }) async {
    try {
      logger.info(
        'Posting attendance event',
        _component,
        {
          'event_id': eventId,
          'event_type': eventType,
          'dedupe_key': dedupeKey,
        },
      );

      final payload = {
        'user_id': testUserId,
        'device_id': testDeviceId,
        'session_id': testSessionId,
        'event_type': eventType,
        'timestamp': timestamp.toIso8601String(),
        'location': {
          'lat': latitude,
          'lng': longitude,
          'accuracy': accuracy,
        },
        'biometric_ok': biometricOk,
        'biometric_timestamp': biometricTimestamp?.toIso8601String(),
        'dedupe_key': dedupeKey,
        'client_event_id': eventId,
      };

      final response = await _supabase.rpc('validate_attendance', params: {
        'event_data': payload,
      });

      final result = response as Map<String, dynamic>;
      
      logger.info(
        'Attendance event response received',
        _component,
        {
          'event_id': eventId,
          'server_status': result['status'],
          'server_reason': result['reason'],
          'duplicate': result['duplicate'],
        },
      );

      metrics.increment(MetricsService.apiCallSuccess);
      return ApiResponse.success(
        status: result['status'] as String,
        reason: result['reason'] as String,
        serverEventId: result['event_id'] as String,
        isDuplicate: result['duplicate'] as bool? ?? false,
      );

    } catch (e) {
      metrics.increment(MetricsService.apiCallFailure);
      final isRetryable = _isRetryableError(e);
      if (isRetryable) {
        metrics.increment(MetricsService.apiRetryable);
      } else {
        metrics.increment(MetricsService.apiNonRetryable);
      }

      logger.error(
        'Failed to post attendance event',
        _component,
        {
          'event_id': eventId,
          'error': e.toString(),
        },
      );

      return ApiResponse.error(
        error: e.toString(),
        isRetryable: isRetryable,
      );
    }
  }

  /// Post heartbeat event to server
  Future<ApiResponse> postHeartbeat({
    required String eventId,
    required String dedupeKey,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    try {
      logger.debug(
        'Posting heartbeat event',
        _component,
        {
          'event_id': eventId,
          'dedupe_key': dedupeKey,
        },
      );

      final payload = {
        'user_id': testUserId,
        'device_id': testDeviceId,
        'session_id': testSessionId,
        'timestamp': timestamp.toIso8601String(),
        'location': {
          'lat': latitude,
          'lng': longitude,
          'accuracy': accuracy,
        },
        'dedupe_key': dedupeKey,
        'client_event_id': eventId,
      };

      final response = await _supabase.rpc('record_heartbeat', params: {
        'heartbeat_data': payload,
      });

      final result = response as Map<String, dynamic>;
      
      logger.debug(
        'Heartbeat response received',
        _component,
        {
          'event_id': eventId,
          'server_status': result['status'],
          'duplicate': result['duplicate'],
        },
      );

      metrics.increment(MetricsService.apiCallSuccess);
      return ApiResponse.success(
        status: result['status'] as String,
        reason: result['reason'] as String,
        serverEventId: result['event_id'] as String,
        isDuplicate: result['duplicate'] as bool? ?? false,
      );

    } catch (e) {
      metrics.increment(MetricsService.apiCallFailure);
      final isRetryable = _isRetryableError(e);
      if (isRetryable) {
        metrics.increment(MetricsService.apiRetryable);
      } else {
        metrics.increment(MetricsService.apiNonRetryable);
      }

      logger.error(
        'Failed to post heartbeat event',
        _component,
        {
          'event_id': eventId,
          'error': e.toString(),
        },
      );

      return ApiResponse.error(
        error: e.toString(),
        isRetryable: isRetryable,
      );
    }
  }

  /// Check if error is retryable
  bool _isRetryableError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // Network/connection errors are retryable
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('timeout') ||
        errorString.contains('socket')) {
      return true;
    }
    
    // Server errors (5xx) are retryable
    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504')) {
      return true;
    }
    
    // Client errors (4xx) are not retryable
    if (errorString.contains('400') ||
        errorString.contains('401') ||
        errorString.contains('403') ||
        errorString.contains('404')) {
      return false;
    }
    
    // Default to retryable for unknown errors
    return true;
  }

  /// Get recent events for reconciliation (for O5)
  /// This will be fully implemented in O5 - Reconciliation phase
  Future<List<Map<String, dynamic>>> getRecentEvents({
    DateTime? since,
    int limit = 100,
  }) async {
    try {
      // Build the base query
      final query = _supabase
          .from('attendance_events')
          .select('*')
          .eq('user_id', testUserId)
          .order('event_timestamp', ascending: false)
          .limit(limit);

      final response = await query;
      final events = List<Map<String, dynamic>>.from(response as List);
      
      // Manual filtering by timestamp if needed (since .gte() is not available on transform builder)
      if (since != null) {
        return events.where((event) {
          final eventTime = DateTime.parse(event['event_timestamp'] as String);
          return eventTime.isAfter(since) || eventTime.isAtSameMomentAs(since);
        }).toList();
      }
      
      return events;

    } catch (e) {
      logger.error(
        'Failed to get recent events',
        _component,
        {'error': e.toString()},
      );
      return [];
    }
  }
}

/// API response wrapper
class ApiResponse {
  final bool success;
  final String? status;
  final String? reason;
  final String? serverEventId;
  final bool isDuplicate;
  final String? error;
  final bool isRetryable;

  ApiResponse.success({
    required this.status,
    required this.reason,
    required this.serverEventId,
    this.isDuplicate = false,
  })  : success = true,
        error = null,
        isRetryable = false;

  ApiResponse.error({
    required this.error,
    required this.isRetryable,
  })  : success = false,
        status = null,
        reason = null,
        serverEventId = null,
        isDuplicate = false;

  @override
  String toString() {
    if (success) {
      return 'ApiResponse.success(status: $status, reason: $reason, duplicate: $isDuplicate)';
    } else {
      return 'ApiResponse.error(error: $error, retryable: $isRetryable)';
    }
  }
}
