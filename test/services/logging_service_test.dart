import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/services/logging_service.dart';

void main() {
  group('LoggingService', () {
    late LoggingService service;

    setUp(() {
      service = LoggingService();
      service.clearLogs();
    });

    tearDown(() {
      service.clearLogs();
    });

    test('info log is added to logs', () {
      service.info('Test message', 'TestComponent', {'key': 'value'});
      
      final logs = service.getRecentLogs(10);
      expect(logs.length, equals(1));
      expect(logs.first.level, equals('INFO'));
      expect(logs.first.message, equals('Test message'));
      expect(logs.first.component, equals('TestComponent'));
    });

    test('error log is added to logs', () {
      service.error('Error message', 'TestComponent', {'error': 'details'});
      
      final logs = service.getRecentLogs(10);
      expect(logs.length, equals(1));
      expect(logs.first.level, equals('ERROR'));
    });

    test('warn log is added to logs', () {
      service.warn('Warning message', 'TestComponent', {'warning': 'info'});
      
      final logs = service.getRecentLogs(10);
      expect(logs.length, equals(1));
      expect(logs.first.level, equals('WARN'));
    });

    test('debug log is added to logs', () {
      service.debug('Debug message', 'TestComponent', {'debug': 'data'});
      
      final logs = service.getRecentLogs(10);
      expect(logs.length, equals(1));
      expect(logs.first.level, equals('DEBUG'));
    });

    test('logs are stored in reverse chronological order', () {
      service.info('First', 'TestComponent');
      service.info('Second', 'TestComponent');
      service.info('Third', 'TestComponent');
      
      final logs = service.getRecentLogs(10);
      expect(logs[0].message, equals('Third'));
      expect(logs[1].message, equals('Second'));
      expect(logs[2].message, equals('First'));
    });

    test('only last 100 logs are kept', () {
      for (int i = 0; i < 150; i++) {
        service.info('Message $i', 'TestComponent');
      }
      
      final logs = service.getRecentLogs(200);
      expect(logs.length, equals(100));
      expect(logs.first.message, equals('Message 149'));
      expect(logs.last.message, equals('Message 50'));
    });

    test('getRecentLogs respects limit parameter', () {
      for (int i = 0; i < 20; i++) {
        service.info('Message $i', 'TestComponent');
      }
      
      final logs = service.getRecentLogs(5);
      expect(logs.length, equals(5));
    });

    test('getLogsAsJson exports logs correctly', () {
      service.info('Test message', 'TestComponent', {'key': 'value'});
      
      final json = service.getLogsAsJson(10);
      expect(json, isA<String>());
      expect(json, contains('Test message'));
      expect(json, contains('TestComponent'));
      expect(json, contains('INFO'));
    });

    test('clearLogs removes all logs', () {
      service.info('Message 1', 'TestComponent');
      service.info('Message 2', 'TestComponent');
      
      service.clearLogs();
      
      final logs = service.getRecentLogs(10);
      expect(logs.isEmpty, isTrue);
    });

    test('UI callback is called when set', () {
      String? callbackMessage;
      service.setUILogCallback((message) {
        callbackMessage = message;
      });
      
      service.info('Test message', 'TestComponent');
      
      expect(callbackMessage, isNotNull);
      expect(callbackMessage, contains('Test message'));
    });

    test('log entry contains timestamp', () {
      final beforeTime = DateTime.now();
      service.info('Test message', 'TestComponent');
      final afterTime = DateTime.now();
      
      final logs = service.getRecentLogs(1);
      expect(logs.first.timestamp.isAfter(beforeTime.subtract(const Duration(seconds: 1))), isTrue);
      expect(logs.first.timestamp.isBefore(afterTime.add(const Duration(seconds: 1))), isTrue);
    });

    test('log entry preserves data', () {
      service.info('Test message', 'TestComponent', {
        'key1': 'value1',
        'key2': 42,
        'key3': true,
      });
      
      final logs = service.getRecentLogs(1);
      expect(logs.first.data['key1'], equals('value1'));
      expect(logs.first.data['key2'], equals(42));
      expect(logs.first.data['key3'], equals(true));
    });
  });

  group('LogEntry', () {
    test('toJson serializes correctly', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
        level: 'INFO',
        message: 'Test message',
        component: 'TestComponent',
        data: {'key': 'value'},
      );

      final json = entry.toJson();
      expect(json['level'], equals('INFO'));
      expect(json['message'], equals('Test message'));
      expect(json['component'], equals('TestComponent'));
      expect(json['data'], isA<Map>());
      expect(json['timestamp'], isA<String>());
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'timestamp': '2024-01-01T12:00:00.000',
        'level': 'ERROR',
        'message': 'Error message',
        'component': 'ErrorComponent',
        'data': {'error': 'details'},
      };

      final entry = LogEntry.fromJson(json);
      expect(entry.level, equals('ERROR'));
      expect(entry.message, equals('Error message'));
      expect(entry.component, equals('ErrorComponent'));
      expect(entry.data['error'], equals('details'));
    });

    test('fromJson handles missing data field', () {
      final json = {
        'timestamp': '2024-01-01T12:00:00.000',
        'level': 'INFO',
        'message': 'Test',
        'component': 'Test',
      };

      final entry = LogEntry.fromJson(json);
      expect(entry.data, isEmpty);
    });
  });
}

