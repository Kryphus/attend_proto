import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/services/metrics_service.dart';

void main() {
  group('MetricsService', () {
    late MetricsService service;

    setUp(() {
      service = MetricsService();
      service.resetAll(); // Start with clean slate for each test
    });

    tearDown(() {
      service.resetAll(); // Clean up after each test
    });

    test('initial counter value is zero', () {
      expect(service.getCounter('test.counter'), equals(0));
    });

    test('increment increases counter by 1', () {
      service.increment('test.counter');
      expect(service.getCounter('test.counter'), equals(1));
      
      service.increment('test.counter');
      expect(service.getCounter('test.counter'), equals(2));
    });

    test('increment by custom amount', () {
      service.increment('test.counter', by: 5);
      expect(service.getCounter('test.counter'), equals(5));
      
      service.increment('test.counter', by: 3);
      expect(service.getCounter('test.counter'), equals(8));
    });

    test('decrement decreases counter by 1', () {
      service.increment('test.counter', by: 10);
      service.decrement('test.counter');
      expect(service.getCounter('test.counter'), equals(9));
    });

    test('decrement by custom amount', () {
      service.increment('test.counter', by: 10);
      service.decrement('test.counter', by: 3);
      expect(service.getCounter('test.counter'), equals(7));
    });

    test('decrement can go negative', () {
      service.decrement('test.counter', by: 5);
      expect(service.getCounter('test.counter'), equals(-5));
    });

    test('getAllCounters returns all counters', () {
      service.increment('counter.a');
      service.increment('counter.b', by: 2);
      service.increment('counter.c', by: 3);

      final counters = service.getAllCounters();
      expect(counters['counter.a'], equals(1));
      expect(counters['counter.b'], equals(2));
      expect(counters['counter.c'], equals(3));
      expect(counters.length, equals(3));
    });

    test('getMetric returns null for non-existent counter', () {
      final metric = service.getMetric('non.existent');
      expect(metric, isNull);
    });

    test('getMetric returns snapshot with metadata', () {
      service.increment('test.counter', by: 5);
      
      final metric = service.getMetric('test.counter');
      expect(metric, isNotNull);
      expect(metric!.name, equals('test.counter'));
      expect(metric.value, equals(5));
      expect(metric.lastUpdated, isA<DateTime>());
    });

    test('getAllMetrics returns sorted list', () {
      service.increment('first');
      Future.delayed(const Duration(milliseconds: 10));
      service.increment('second');
      Future.delayed(const Duration(milliseconds: 10));
      service.increment('third');

      final metrics = service.getAllMetrics();
      expect(metrics.length, equals(3));
      expect(metrics, isA<List<MetricSnapshot>>());
      // Most recent should be first (sorted by lastUpdated desc)
    });

    test('resetCounter removes specific counter', () {
      service.increment('counter.a');
      service.increment('counter.b');
      
      service.resetCounter('counter.a');
      
      expect(service.getCounter('counter.a'), equals(0));
      expect(service.getCounter('counter.b'), equals(1));
    });

    test('resetAll clears all counters', () {
      service.increment('counter.a');
      service.increment('counter.b');
      service.increment('counter.c');
      
      service.resetAll();
      
      expect(service.getCounter('counter.a'), equals(0));
      expect(service.getCounter('counter.b'), equals(0));
      expect(service.getCounter('counter.c'), equals(0));
      expect(service.getAllCounters().isEmpty, isTrue);
    });

    test('toJson exports metrics as JSON string', () {
      service.increment('test.counter', by: 5);
      
      final json = service.toJson();
      expect(json, isA<String>());
      expect(json, contains('test.counter'));
      expect(json, contains('5'));
      expect(json, contains('timestamp'));
      expect(json, contains('metrics'));
    });

    test('predefined counter names are available', () {
      // Just verify constants exist
      expect(MetricsService.captureSuccess, equals('capture.success'));
      expect(MetricsService.captureFailure, equals('capture.failure'));
      expect(MetricsService.eventConfirmed, equals('event.confirmed'));
      expect(MetricsService.syncAttempt, equals('sync.attempt'));
      expect(MetricsService.apiCallSuccess, equals('api.call_success'));
    });

    test('concurrent operations work correctly', () {
      service.increment('test.counter', by: 5);
      service.decrement('test.counter', by: 2);
      service.increment('test.counter');
      
      expect(service.getCounter('test.counter'), equals(4));
    });

    test('lastUpdated timestamp is updated on changes', () {
      final beforeTime = DateTime.now();
      service.increment('test.counter');
      final afterTime = DateTime.now();
      
      final metric = service.getMetric('test.counter');
      expect(metric, isNotNull);
      expect(metric!.lastUpdated.isAfter(beforeTime.subtract(const Duration(seconds: 1))), isTrue);
      expect(metric.lastUpdated.isBefore(afterTime.add(const Duration(seconds: 1))), isTrue);
    });
  });

  group('MetricSnapshot', () {
    test('toJson serializes correctly', () {
      final snapshot = MetricSnapshot(
        name: 'test.metric',
        value: 42,
        lastUpdated: DateTime(2024, 1, 1, 12, 0, 0),
      );

      final json = snapshot.toJson();
      expect(json['name'], equals('test.metric'));
      expect(json['value'], equals(42));
      expect(json['last_updated'], isA<String>());
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'name': 'test.metric',
        'value': 42,
        'last_updated': '2024-01-01T12:00:00.000',
      };

      final snapshot = MetricSnapshot.fromJson(json);
      expect(snapshot.name, equals('test.metric'));
      expect(snapshot.value, equals(42));
      expect(snapshot.lastUpdated, isA<DateTime>());
    });

    test('toString formats correctly', () {
      final snapshot = MetricSnapshot(
        name: 'test.metric',
        value: 42,
        lastUpdated: DateTime.now(),
      );

      final string = snapshot.toString();
      expect(string, contains('test.metric'));
      expect(string, contains('42'));
      expect(string, contains('ago'));
    });
  });
}

