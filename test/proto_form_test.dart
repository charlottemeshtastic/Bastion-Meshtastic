import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/generated/meshtastic/module_config.pb.dart';
import 'package:bastion/proto_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/protobuf.dart';

Future<void> pumpForm(WidgetTester tester, Widget form) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: form))),
    );

void main() {
  test('labels split camelCase field names', () {
    expect(ProtoFieldList.label('positionBroadcastSecs'), 'Position broadcast secs');
    expect(ProtoFieldList.label('txEnabled'), 'Tx enabled');
  });

  testWidgets('edits bools, numbers and enums in place', (tester) async {
    final draft = Config_PositionConfig(positionBroadcastSecs: 900);
    var changes = 0;
    await pumpForm(tester, ProtoFieldList(
      message: draft,
      writable: () => draft,
      changed: () => changes++,
    ));

    await tester.tap(find.widgetWithText(SwitchListTile, 'Fixed position'));
    await tester.pump();
    expect(draft.fixedPosition, isTrue);

    await tester.enterText(find.widgetWithText(TextField, 'Position broadcast secs'), '1800');
    expect(draft.positionBroadcastSecs, 1800);

    await tester.enterText(find.widgetWithText(TextField, 'Position broadcast secs'), '-5');
    await tester.pump();
    expect(draft.positionBroadcastSecs, 1800, reason: 'unsigned field rejects negatives');
    expect(find.text('Enter a whole number, 0 or more'), findsOneWidget);

    final gpsMode = find.widgetWithText(DropdownButtonFormField<ProtobufEnum>, 'Gps mode');
    await tester.ensureVisible(gpsMode);
    await tester.pumpAndSettle();
    await tester.tap(gpsMode);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enabled').last);
    await tester.pumpAndSettle();
    expect(draft.gpsMode, Config_PositionConfig_GpsMode.ENABLED);
    expect(changes, greaterThanOrEqualTo(3));
  });

  testWidgets('nested messages are created only when edited', (tester) async {
    final draft = ModuleConfig_MQTTConfig();
    final original = draft.deepCopy();
    await pumpForm(tester, ProtoFieldList(
      message: draft,
      writable: () => draft,
      changed: () {},
    ));

    await tester.tap(find.text('Map report settings'));
    await tester.pumpAndSettle();
    expect(draft, original, reason: 'expanding must not change the draft');

    await tester.enterText(find.widgetWithText(TextField, 'Publish interval secs'), '3600');
    expect(draft.hasMapReportSettings(), isTrue);
    expect(draft.mapReportSettings.publishIntervalSecs, 3600);
  });
}
