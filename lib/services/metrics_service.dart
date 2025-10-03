import 'dart:convert';

/// Lightweight metrics service for tracking counters
/// Tracks success/failure/retry counts for observability
class MetricsService {
  static final MetricsService _instance = MetricsService._internal();
  factory MetricsService() => _instance;
  MetricsService._internal();

  final Map<String, int> _counters = {};
  final Map<String, DateTime> _lastUpdated = {};

  /// Increment a counter by name
  void increment(String counterName, {int by = 1}) {
    _counters[counterName] = (_counters[counterName] ?? 0) + by;
    _lastUpdated[counterName] = DateTime.now();
  }

  /// Decrement a counter by name
  void decrement(String counterName, {int by = 1}) {
    _counters[counterName] = (_counters[counterName] ?? 0) - by;
    _lastUpdated[counterName] = DateTime.now();
  }

  /// Get counter value
  int getCounter(String counterName) {
    return _counters[counterName] ?? 0;
  }

  /// Get all counters
  Map<String, int> getAllCounters() {
    return Map.from(_counters);
  }

  /// Get counter with metadata
  MetricSnapshot? getMetric(String counterName) {
    final value = _counters[counterName];
    final lastUpdated = _lastUpdated[counterName];
    
    if (value == null) return null;
    
    return MetricSnapshot(
      name: counterName,
      value: value,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }

  /// Get all metrics with metadata
  List<MetricSnapshot> getAllMetrics() {
    return _counters.entries.map((entry) {
      return MetricSnapshot(
        name: entry.key,
        value: entry.value,
        lastUpdated: _lastUpdated[entry.key] ?? DateTime.now(),
      );
    }).toList()
      ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
  }

  /// Reset a specific counter
  void resetCounter(String counterName) {
    _counters.remove(counterName);
    _lastUpdated.remove(counterName);
  }

  /// Reset all counters
  void resetAll() {
    _counters.clear();
    _lastUpdated.clear();
  }

  /// Export metrics as JSON
  String toJson() {
    final metrics = getAllMetrics().map((m) => m.toJson()).toList();
    return jsonEncode({
      'timestamp': DateTime.now().toIso8601String(),
      'metrics': metrics,
    });
  }

  // Predefined counter names for common operations
  static const String captureSuccess = 'capture.success';
  static const String captureFailure = 'capture.failure';
  static const String captureSignIn = 'capture.sign_in';
  static const String captureSignOut = 'capture.sign_out';
  static const String captureHeartbeat = 'capture.heartbeat';
  
  static const String ruleViolation = 'rule.violation';
  static const String rulePass = 'rule.pass';
  static const String ruleGeofence = 'rule.geofence_violation';
  static const String ruleTimeWindow = 'rule.time_window_violation';
  static const String ruleAccuracy = 'rule.accuracy_violation';
  static const String ruleBiometric = 'rule.biometric_violation';
  static const String ruleSequence = 'rule.sequence_violation';
  static const String ruleTrustedDevice = 'rule.trusted_device_violation';
  
  static const String outboxEnqueued = 'outbox.enqueued';
  static const String outboxDequeued = 'outbox.dequeued';
  static const String outboxSyncSuccess = 'outbox.sync_success';
  static const String outboxSyncFailure = 'outbox.sync_failure';
  static const String outboxRetry = 'outbox.retry';
  static const String outboxDuplicate = 'outbox.duplicate';
  
  static const String syncAttempt = 'sync.attempt';
  static const String syncSuccess = 'sync.success';
  static const String syncFailure = 'sync.failure';
  static const String syncBatchProcessed = 'sync.batch_processed';
  
  static const String eventConfirmed = 'event.confirmed';
  static const String eventRejected = 'event.rejected';
  static const String eventPending = 'event.pending';
  
  static const String reconcileAttempt = 'reconcile.attempt';
  static const String reconcileSuccess = 'reconcile.success';
  static const String reconcileFailure = 'reconcile.failure';
  static const String reconcileEventsUpdated = 'reconcile.events_updated';
  
  static const String apiCallSuccess = 'api.call_success';
  static const String apiCallFailure = 'api.call_failure';
  static const String apiRetryable = 'api.retryable_error';
  static const String apiNonRetryable = 'api.non_retryable_error';
}

/// Snapshot of a metric at a point in time
class MetricSnapshot {
  final String name;
  final int value;
  final DateTime lastUpdated;

  MetricSnapshot({
    required this.name,
    required this.value,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'value': value,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }

  factory MetricSnapshot.fromJson(Map<String, dynamic> json) {
    return MetricSnapshot(
      name: json['name'],
      value: json['value'],
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }

  @override
  String toString() {
    return '$name: $value (updated ${_formatTimeAgo(lastUpdated)})';
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Global metrics instance
final metrics = MetricsService();

