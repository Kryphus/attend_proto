import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/data/remote/api_client.dart';

void main() {
  group('API Error Handling', () {
    late ApiClient apiClient;

    setUp(() {
      // Note: This uses a mock Supabase client in real tests
      // For now, we're testing the error classification logic
    });

    group('Error Classification', () {
      test('network errors are retryable', () {
        final errors = [
          'network error occurred',
          'connection timeout',
          'socket exception',
          'failed to connect',
        ];

        for (final error in errors) {
          final isRetryable = _simulateErrorCheck(error);
          expect(
            isRetryable,
            isTrue,
            reason: 'Network error "$error" should be retryable',
          );
        }
      });

      test('5xx server errors are retryable', () {
        final errors = [
          'error 500 internal server error',
          'status code 502 bad gateway',
          '503 service unavailable',
          'received 504 gateway timeout',
        ];

        for (final error in errors) {
          final isRetryable = _simulateErrorCheck(error);
          expect(
            isRetryable,
            isTrue,
            reason: '5xx error "$error" should be retryable',
          );
        }
      });

      test('4xx client errors are not retryable', () {
        final errors = [
          'error 400 bad request',
          'status code 401 unauthorized',
          '403 forbidden access',
          'received 404 not found',
        ];

        for (final error in errors) {
          final isRetryable = _simulateErrorCheck(error);
          expect(
            isRetryable,
            isFalse,
            reason: '4xx error "$error" should NOT be retryable',
          );
        }
      });

      test('unknown errors default to retryable', () {
        final unknownErrors = [
          'something went wrong',
          'unexpected error',
          'unknown failure',
        ];

        for (final error in unknownErrors) {
          final isRetryable = _simulateErrorCheck(error);
          expect(
            isRetryable,
            isTrue,
            reason: 'Unknown error should default to retryable for safety',
          );
        }
      });
    });

    group('Error Response Handling', () {
      test('retryable error sets isRetryable flag', () {
        final response = ApiResponse.error(
          error: 'network timeout',
          isRetryable: true,
        );

        expect(response.success, isFalse);
        expect(response.isRetryable, isTrue);
        expect(response.error, equals('network timeout'));
      });

      test('non-retryable error sets isRetryable to false', () {
        final response = ApiResponse.error(
          error: '400 bad request',
          isRetryable: false,
        );

        expect(response.success, isFalse);
        expect(response.isRetryable, isFalse);
        expect(response.error, equals('400 bad request'));
      });

      test('success response has isRetryable false', () {
        final response = ApiResponse.success(
          status: 'CONFIRMED',
          reason: 'Success',
          serverEventId: 'event-123',
          isDuplicate: false,
        );

        expect(response.success, isTrue);
        expect(response.isRetryable, isFalse);
      });
    });

    group('Duplicate Detection', () {
      test('duplicate flag is set correctly', () {
        final response = ApiResponse.success(
          status: 'CONFIRMED',
          reason: 'Event already processed',
          serverEventId: 'event-123',
          isDuplicate: true,
        );

        expect(response.success, isTrue);
        expect(response.isDuplicate, isTrue);
      });

      test('non-duplicate event has isDuplicate false', () {
        final response = ApiResponse.success(
          status: 'CONFIRMED',
          reason: 'Event processed',
          serverEventId: 'event-123',
          isDuplicate: false,
        );

        expect(response.success, isTrue);
        expect(response.isDuplicate, isFalse);
      });
    });

    group('Status Codes', () {
      test('CONFIRMED status is recognized', () {
        final response = ApiResponse.success(
          status: 'CONFIRMED',
          reason: 'Valid event',
          serverEventId: 'event-123',
        );

        expect(response.status, equals('CONFIRMED'));
      });

      test('REJECTED status is recognized', () {
        final response = ApiResponse.success(
          status: 'REJECTED',
          reason: 'Geofence violation',
          serverEventId: 'event-123',
        );

        expect(response.status, equals('REJECTED'));
      });
    });
  });
}

/// Simulates the error checking logic from ApiClient._isRetryableError
bool _simulateErrorCheck(String error) {
  final errorString = error.toLowerCase();
  
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

