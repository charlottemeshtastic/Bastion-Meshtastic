import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion_meshtastic/services/bot/bot_controller.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'package:bastion_meshtastic/screens/automations/bot_panel.dart';
import 'radio_session_test.dart' show FakeTransport;

void main() {
  testWidgets(
    'Bot Mode toggle arms current radio, turns off and disables on disconnect',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session = RadioSession(nonce: () => 123);
      final transport = FakeTransport();
      final bot = BotController(session);
      await bot.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [BotPanel(bot: bot)]),
          ),
        ),
      );
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('bot-mode-toggle')))
            .onChanged,
        isNull,
      );
      await session.connect(transport);
      transport.emit(pb.FromRadio(myInfo: pb.MyNodeInfo(myNodeNum: 42)));
      transport.emit(pb.FromRadio(configCompleteId: 123));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bot-mode-toggle')));
      await tester.pumpAndSettle();
      expect(bot.enabled, isTrue);
      expect(bot.armedRadio, 42);
      await tester.tap(find.byKey(const Key('bot-mode-toggle')));
      await tester.pumpAndSettle();
      expect(bot.enabled, isFalse);
      await tester.tap(find.byKey(const Key('bot-mode-toggle')));
      await tester.pumpAndSettle();
      await session.disconnect();
      await tester.pumpAndSettle();
      expect(bot.enabled, isFalse);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('bot-mode-toggle')))
            .onChanged,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      bot.dispose();
      session.dispose();
      await transport.finish();
    },
  );
}
