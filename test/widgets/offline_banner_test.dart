import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/widgets/offline_banner.dart';

void main() {
  group('OfflineBanner', () {
    testWidgets('renders offline text and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineBanner(),
          ),
        ),
      );

      expect(find.text('Offline Mode - Events will sync when online'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('close icon is shown only when onDismiss provided', (tester) async {
      // Without onDismiss
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineBanner(),
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsNothing);

      // With onDismiss
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineBanner(onDismiss: () { dismissed = true; }),
          ),
        ),
      );
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });
  });
}


