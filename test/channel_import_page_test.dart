import 'package:bastion/channel_share_page.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('import offers QR scanning and previews a pasted link', (tester) async {
    final radio = MeshtasticRadioCoordinator();
    addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(home: ChannelImportPage(radio: radio)));

    expect(find.text('Scan channel QR code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'https://meshtastic.org/e/#CgMSAQESBggBQANIAQ');
    await tester.pump();
    expect(find.text('1. (default name)'), findsOneWidget);
  });
}
