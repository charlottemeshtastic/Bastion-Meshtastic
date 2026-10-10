import 'package:bastion/map_page.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('map explains how to get pins when no radio is connected', (tester) async {
    final radio = MeshtasticRadioCoordinator();
    addTearDown(radio.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MapPage(radio: radio))));
    await tester.pump();
    expect(find.text('Connect a radio to show node positions'), findsOneWidget);
    expect(find.text('OpenStreetMap contributors'), findsOneWidget);
  });
}
