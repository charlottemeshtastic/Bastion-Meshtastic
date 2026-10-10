import 'package:bastion/radio_settings_page.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('radio settings are locked until a radio is ready', (tester) async {
    final radio = MeshtasticRadioCoordinator();
    addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(home: RadioSettingsPage(radio: radio)));

    expect(find.text('Radio not ready'), findsOneWidget);
    for (final title in ['Owner', 'LoRa', 'Channels', 'Device', 'Position']) {
      final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, title));
      expect(tile.enabled, isFalse, reason: title);
    }

    await tester.tap(find.text('LoRa'));
    await tester.pumpAndSettle();
    expect(find.text('Radio settings'), findsOneWidget);
  });
}
