import 'package:flutter_test/flutter_test.dart';
import '../../../lib/data/remote/api_client.dart';
import '../../../lib/services/logging_service.dart';

void main() {
  group('ApiClient', () {
    setUp(() {
      // Initialize logger for tests
      logger.setUILogCallback((message) => print(message));
    });

    group('ApiResponse', () {
      test('success constructor creates correct structure', () {
        final response = ApiResponse.success(
          status: 'CONFIRMED',
          reason: 'Event validated successfully',
          serverEventId: 'server-123',
          isDuplicate: false,
        );

        expect(response.success, true);
        expect(response.status, 'CONFIRMED');
        expect(response.reason, 'Event validated successfully');
        expect(response.serverEventId, 'server-123');
        expect(response.isDuplicate, false);
        expect(response.error, null);
        expect(response.isRetryable, false);
      });

      test('error constructor creates correct structure', () {
        final response = ApiResponse.error(
          error: 'Network timeout',
          isRetryable: true,
        );

        expect(response.success, false);
        expect(response.error, 'Network timeout');
        expect(response.isRetryable, true);
        expect(response.status, null);
        expect(response.reason, null);
        expect(response.serverEventId, null);
        expect(response.isDuplicate, false);
      });

      test('toString provides readable output for success', () {
        final response = ApiResponse.success(
          status: 'CONFIRMED',
          reason: 'Test reason',
          serverEventId: 'test-id',
          isDuplicate: false,
        );

        expect(
          response.toString(),
          'ApiResponse.success(status: CONFIRMED, reason: Test reason, duplicate: false)',
        );
      });

      test('toString provides readable output for error', () {
        final response = ApiResponse.error(
          error: 'Test error',
          isRetryable: true,
        );

        expect(
          response.toString(),
          'ApiResponse.error(error: Test error, retryable: true)',
        );
      });
    });

    group('Error Retryability Logic', () {
      late ApiClient apiClient;

      setUp(() {
        // We can't easily test the private _isRetryableError method directly,
        // but we can verify the logic through the class structure
        // For now, we'll just verify the test constants are set correctly
      });

      test('test user ID is correctly set', () {
        expect(ApiClient.testUserId, '550e8400-e29b-41d4-a716-446655440000');
      });

      test('test device ID is correctly set', () {
        expect(ApiClient.testDeviceId, '550e8400-e29b-41d4-a716-446655440001');
      });

      test('test session ID is correctly set', () {
        expect(ApiClient.testSessionId, '550e8400-e29b-41d4-a716-446655440002');
      });
    });

    group('ApiResponse behavior', () {
      test('success response has correct defaults', () {
        final response = ApiResponse.success(
          status: 'CONFIRMED',
          reason: 'OK',
          serverEventId: 'id-123',
        );

        expect(response.success, true);
        expect(response.isDuplicate, false);
        expect(response.isRetryable, false);
        expect(response.error, null);
      });

      test('error response has correct defaults', () {
        final response = ApiResponse.error(
          error: 'Failed',
          isRetryable: false,
        );

        expect(response.success, false);
        expect(response.status, null);
        expect(response.reason, null);
        expect(response.serverEventId, null);
        expect(response.isDuplicate, false);
      });

      test('can create duplicate success response', () {
        final response = ApiResponse.success(
          status: 'CONFIRMED',
          reason: 'Already processed',
          serverEventId: 'existing-id',
          isDuplicate: true,
        );

        expect(response.success, true);
        expect(response.isDuplicate, true);
      });

      test('can create retryable error response', () {
        final response = ApiResponse.error(
          error: '500 Internal Server Error',
          isRetryable: true,
        );

        expect(response.success, false);
        expect(response.isRetryable, true);
      });

      test('can create non-retryable error response', () {
        final response = ApiResponse.error(
          error: '400 Bad Request',
          isRetryable: false,
        );

        expect(response.success, false);
        expect(response.isRetryable, false);
      });
    });
  });
}
