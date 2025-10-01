import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/widgets/status_pill.dart';

void main() {
  group('StatusPill', () {
    testWidgets('renders PENDING label and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusPill(status: 'PENDING')),
        ),
      );

      expect(find.text('PENDING'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets('renders CONFIRMED label and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusPill(status: 'CONFIRMED')),
        ),
      );

      expect(find.text('CONFIRMED'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('renders REJECTED label and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StatusPill(status: 'REJECTED')),
        ),
      );

      expect(find.text('REJECTED'), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });
  });
}


