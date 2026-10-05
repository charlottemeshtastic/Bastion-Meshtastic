import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/screens/automations/automations_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('add, simulate, disable and persist a battery rule', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AutomationsPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ADD RULE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Battery below 20%'));
    await tester.pumpAndSettle();
    expect(find.text('Battery watch'), findsOneWidget);
    await tester.tap(find.text('TEST WITH SIMULATED DATA'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DEMO-REPEATER battery below'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bastion.automation.rules.v1'), contains('"enabled":false'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AutomationsPage())));
    await tester.pumpAndSettle();
    expect(find.text('Battery watch'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
}
