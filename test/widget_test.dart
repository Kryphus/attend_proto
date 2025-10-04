import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/main.dart';
import 'package:attend_proto/data/local/db.dart';
import 'package:attend_proto/data/local/event_log_repo.dart';
import 'package:attend_proto/data/local/outbox_repo.dart';
import 'package:attend_proto/data/local/sync_cursor_repo.dart';
import 'package:attend_proto/sync/sync_service.dart';
import 'package:attend_proto/sync/connectivity_service.dart';
import 'package:attend_proto/domain/attendance_service.dart';
import 'package:attend_proto/services/biometric_service.dart';
import 'package:drift/native.dart';

void main() {
  group('Attendance App Tests', () {
    late AppDatabase database;
    late SyncService syncService;
    late AttendanceService attendanceService;
    late ConnectivityService connectivityService;

    setUp(() {
      // Create test database and services
      database = AppDatabase.withExecutor(NativeDatabase.memory());
      final eventLogRepo = EventLogRepo(database);
      final outboxRepo = OutboxRepo(database);
      final syncCursorRepo = SyncCursorRepo(database);
      connectivityService = ConnectivityService();
      
      syncService = SyncService(
        connectivityService: connectivityService,
        syncCursorRepo: syncCursorRepo,
        apiClient: null, // No API client for widget tests
      );

      final biometricService = BiometricService();
      attendanceService = AttendanceService(
        eventLogRepo: eventLogRepo,
        outboxRepo: outboxRepo,
        biometricService: biometricService,
      );
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('App loads and shows main interface', (WidgetTester tester) async {
      // Build our app and trigger a frame
      await tester.pumpWidget(MyApp(
        syncService: syncService,
        attendanceService: attendanceService,
        connectivityService: connectivityService,
      ));

      // Wait for app to build and all async operations to complete
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify that the main elements are present
      expect(find.text('TagMeIn+'), findsOneWidget);
      expect(find.text('Set Geofence'), findsOneWidget);
      // Check In button shows different text when event is not active
      expect(find.textContaining('Event Not Active', findRichText: true), findsWidgets);
      expect(find.text('Set Event Duration'), findsOneWidget);
    });

    testWidgets('Check In button is present in the UI', (WidgetTester tester) async {
      await tester.pumpWidget(MyApp(
        syncService: syncService,
        attendanceService: attendanceService,
        connectivityService: connectivityService,
      ));
      
      // Wait for the UI to build
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify the check-in related text is present
      // The button can show either "Check In" or "Event Not Active"
      final hasCheckIn = find.text('Check In').evaluate().isNotEmpty;
      final hasEventNotActive = find.text('Event Not Active').evaluate().isNotEmpty;
      
      expect(
        hasCheckIn || hasEventNotActive,
        isTrue,
        reason: 'Expected to find either "Check In" or "Event Not Active" button text',
      );
    });

    testWidgets('Main UI components are present', (WidgetTester tester) async {
      await tester.pumpWidget(MyApp(
        syncService: syncService,
        attendanceService: attendanceService,
        connectivityService: connectivityService,
      ));
      
      // Wait for the UI to build
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify key UI components exist
      // Check for geofence button
      expect(find.text('Set Geofence'), findsOneWidget);
      
      // Check for event duration button
      expect(find.text('Set Event Duration'), findsOneWidget);
      
      // The app should have loaded successfully with main components visible
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
