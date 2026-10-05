import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/services/automations/automation_engine.dart';
import 'package:bastion_meshtastic/screens/automations/rule_editor_page.dart';

void main() {
  testWidgets('validates thresholds and returns a targeted custom rule', (
    tester,
  ) async {
    AutomationRule? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<AutomationRule>(
                  MaterialPageRoute(
                    builder: (_) => const RuleEditorPage(
                      currentRadio: 42,
                      radios: [42],
                      nodes: [],
                    ),
                  ),
                );
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rule name'),
      'Ridge watch',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Battery threshold (%)'),
      '101',
    );
    await tester.ensureVisible(find.text('SAVE RULE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE RULE'));
    await tester.pumpAndSettle();
    expect(find.text('Use 1–100%.'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Battery threshold (%)'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Battery threshold (%)'),
      '35',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Target node ID (optional)'),
      'A1B2C3D4',
    );
    await tester.ensureVisible(find.text('SAVE RULE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE RULE'));
    await tester.pumpAndSettle();
    expect(result!.name, 'Ridge watch');
    expect(result!.threshold, 35);
    expect(result!.radioId, 42);
    expect(result!.nodeId, '!a1b2c3d4');
    expect(tester.takeException(), isNull);
  });
}
