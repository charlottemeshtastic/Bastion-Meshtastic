import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/main.dart';

void main() {
  testWidgets('Bastion exposes five functional field tabs', (tester) async {
    await tester.pumpWidget(const BastionMeshtasticApp());
    expect(find.text('MESHTASTIC EDITION'), findsOneWidget);
    expect(find.text('MESH COMMAND'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('BOT MODE'), findsOneWidget);
    expect(find.text('DESTINATION'), findsOneWidget);
    expect(find.text('Channel 0 • Broadcast'), findsOneWidget);
    expect(find.text('QUEUED'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.build_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('FIELD TOOLS'), findsWidgets);
    expect(find.text('BATTERY RUNTIME'), findsOneWidget);
    expect(find.text('RSSI FIELD REFERENCE'), findsOneWidget);
    expect(find.text('DEPLOYMENT CHECKLIST'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Low-power field mode'), findsOneWidget);
  });
}
