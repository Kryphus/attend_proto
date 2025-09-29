import 'dart:convert';

/// Simple logging service for structured logging
/// Integrates with existing _trackingLogs system and provides structured logging
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  final List<LogEntry> _logs = [];
  Function(String)? _uiLogCallback;

  /// Set callback to add logs to UI (e.g., _addTrackingLog)
  void setUILogCallback(Function(String) callback) {
    _uiLogCallback = callback;
  }

  /// Log structured data
  void logStructured({
    required String level,
    required String message,
    required String component,
    Map<String, dynamic>? data,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      component: component,
      data: data ?? {},
    );

    _logs.insert(0, entry);
    
    // Keep only last 100 logs
    if (_logs.length > 100) {
      _logs.removeRange(100, _logs.length);
    }

    // Also send to UI if callback is set
    _uiLogCallback?.call(_formatForUI(entry));

    // Print to console for debugging
    print(_formatForConsole(entry));
  }

  /// Log info level
  void info(String message, String component, [Map<String, dynamic>? data]) {
    logStructured(
      level: 'INFO',
      message: message,
      component: component,
      data: data,
    );
  }

  /// Log error level
  void error(String message, String component, [Map<String, dynamic>? data]) {
    logStructured(
      level: 'ERROR',
      message: message,
      component: component,
      data: data,
    );
  }

  /// Log warning level
  void warn(String message, String component, [Map<String, dynamic>? data]) {
    logStructured(
      level: 'WARN',
      message: message,
      component: component,
      data: data,
    );
  }

  /// Log debug level
  void debug(String message, String component, [Map<String, dynamic>? data]) {
    logStructured(
      level: 'DEBUG',
      message: message,
      component: component,
      data: data,
    );
  }

  /// Get recent logs
  List<LogEntry> getRecentLogs([int limit = 50]) {
    return _logs.take(limit).toList();
  }

  /// Get logs as JSON string for debugging
  String getLogsAsJson([int limit = 50]) {
    final recentLogs = getRecentLogs(limit);
    return jsonEncode(recentLogs.map((log) => log.toJson()).toList());
  }

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
  }

  String _formatForUI(LogEntry entry) {
    final timeStr = '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';
    
    final icon = _getIconForLevel(entry.level);
    return '$timeStr $icon [${entry.component}] ${entry.message}';
  }

  String _formatForConsole(LogEntry entry) {
    final timeStr = entry.timestamp.toIso8601String();
    final dataStr = entry.data.isNotEmpty ? ' | ${jsonEncode(entry.data)}' : '';
    return '[$timeStr] ${entry.level} [${entry.component}] ${entry.message}$dataStr';
  }

  String _getIconForLevel(String level) {
    switch (level) {
      case 'INFO':
        return 'ℹ️';
      case 'ERROR':
        return '❌';
      case 'WARN':
        return '⚠️';
      case 'DEBUG':
        return '🔍';
      default:
        return '📝';
    }
  }
}

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String component;
  final Map<String, dynamic> data;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    required this.component,
    required this.data,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level,
      'message': message,
      'component': component,
      'data': data,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      level: json['level'],
      message: json['message'],
      component: json['component'],
      data: Map<String, dynamic>.from(json['data'] ?? {}),
    );
  }
}

/// Global logger instance
final logger = LoggingService();
