import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/services/bot/bot_engine.dart';
import 'package:bastion_meshtastic/screens/automations/bot_settings_page.dart';

void main() {
  testWidgets(
    'editor validates reply, selects channel and returns custom settings',
    (tester) async {
      BotSettings? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('OPEN'),
                onPressed: () async {
                  saved = await Navigator.of(context).push<BotSettings>(
                    MaterialPageRoute(
                      builder: (_) => const BotSettingsPage(
                        settings: BotSettings(),
                        channels: [0, 1],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Custom away reply'),
        '',
      );
      await tester.tap(find.text('SAVE BOT SETTINGS'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.textContaining('Reply plus the bot marker'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Custom away reply'),
        'BCS is out exploring.',
      );
      await tester.ensureVisible(find.text('Reply to channel commands'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply to channel commands'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Channel 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVE BOT SETTINGS'));
      await tester.pumpAndSettle();
      expect(saved?.reply, 'BCS is out exploring.');
      expect(saved?.channelCommands, isTrue);
      expect(saved?.channels, [1]);
      expect(saved?.cooldownMinutes, 5);
    },
  );
}
