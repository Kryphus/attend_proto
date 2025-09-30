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

      // Wait for app to build
      await tester.pumpAndSettle();

      // Verify that the main elements are present
      expect(find.text('TagMeIn+'), findsOneWidget);
      expect(find.text('Set Geofence'), findsOneWidget);
      expect(find.text('Check In'), findsOneWidget);
      expect(find.text('Set Event Duration'), findsOneWidget);
    });

    testWidgets('Check In button is disabled when no event duration is set', (WidgetTester tester) async {
      await tester.pumpWidget(MyApp(
        syncService: syncService,
        attendanceService: attendanceService,
        connectivityService: connectivityService,
      ));
      await tester.pumpAndSettle();

      // Find the Check In button
      final checkInButton = find.widgetWithText(ElevatedButton, 'Check In');
      expect(checkInButton, findsOneWidget);

      // Button should be disabled (grey) when no event is set
      final button = tester.widget<ElevatedButton>(checkInButton);
      expect(button.onPressed, isNull); // Disabled buttons have null onPressed
    });

    testWidgets('Activity Log is visible', (WidgetTester tester) async {
      await tester.pumpWidget(MyApp(
        syncService: syncService,
        attendanceService: attendanceService,
        connectivityService: connectivityService,
      ));
      await tester.pumpAndSettle();

      // Verify Activity Log section exists
      expect(find.text('Activity Log'), findsOneWidget);
    });
  });
}
