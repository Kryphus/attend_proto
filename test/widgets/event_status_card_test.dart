import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attend_proto/widgets/event_status_card.dart';

void main() {
  group('EventStatusCard', () {
    testWidgets('shows pending count and formatted last sync', (tester) async {
      final now = DateTime.now();
      final oneMinuteAgo = now.subtract(const Duration(minutes: 1));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventStatusCard(
              pendingCount: 3,
              lastSyncTime: oneMinuteAgo,
              lastReconcileTime: now,
            ),
          ),
        ),
      );

      expect(find.text('Pending Events'), findsOneWidget);
      expect(find.text('3 events'), findsOneWidget);
      expect(find.textContaining('Last Sync'), findsOneWidget);
      expect(find.textContaining('ago'), findsWidgets);
      expect(find.text('Last Reconcile'), findsOneWidget);
    });

    testWidgets('shows None when pendingCount is 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EventStatusCard(
              pendingCount: 0,
              lastSyncTime: null,
              lastReconcileTime: null,
            ),
          ),
        ),
      );

      expect(find.text('None'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
    });
  });
}


