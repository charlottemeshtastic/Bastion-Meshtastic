import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Bastion shell exposes six tabs', (tester) async {
    await tester.pumpWidget(const BastionMeshtasticApp());
    expect(find.text('OFFLINE MESH COMPANION'), findsOneWidget);
    for (final name in ['NODES', 'CHATS', 'MAP', 'TOOLS', 'AUTO', 'SETTINGS']) {
      expect(find.text(name), findsWidgets);
    }
    await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('MESH CHATS'), findsOneWidget);
    expect(find.text('SEND MESSAGE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
