import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/main.dart';

void main() {
  group('Attendance App Tests', () {
    testWidgets('App loads and shows main interface', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Verify that the main elements are present
      expect(find.text('Attendance Tracker'), findsOneWidget);
      expect(find.text('Set Geofence'), findsOneWidget);
      expect(find.text('Check In'), findsOneWidget);
      expect(find.text('Presence Status:'), findsOneWidget);
      expect(find.text('Current Geofence:'), findsOneWidget);
      expect(find.text('No geofence set'), findsOneWidget);
    });

    testWidgets('Check In button shows error when no geofence is set', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());

      // Tap the Check In button without setting a geofence
      await tester.tap(find.text('Check In'));
      await tester.pump();

      // Verify error message appears
      expect(find.text('Please set a geofence first'), findsOneWidget);
    });

    testWidgets('Geofence information display updates correctly', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());

      // Initially should show "No geofence set"
      expect(find.text('No geofence set'), findsOneWidget);

      // The actual geofence setting would require navigation to map screen
      // which is more complex to test in unit tests
    });
  });
}
