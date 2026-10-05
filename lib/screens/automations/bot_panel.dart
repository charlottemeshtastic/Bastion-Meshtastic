import 'package:flutter/material.dart';
import '../../services/bot/bot_controller.dart';
import '../../services/bot/bot_engine.dart';
import '../../services/meshtastic/radio_session.dart';
import 'bot_settings_page.dart';

class BotPanel extends StatelessWidget {
  const BotPanel({super.key, required this.bot});
  final BotController bot;
  Future<void> _edit(BuildContext context) async {
    final channels =
        bot.session.channels.values
            .where((c) => c.role.name != 'DISABLED')
            .map((c) => c.index)
            .toList()
          ..sort();
    final value = await Navigator.of(context).push<BotSettings>(
      MaterialPageRoute(
        builder: (_) =>
            BotSettingsPage(settings: bot.settings, channels: channels),
      ),
    );
    if (value != null) {
      await bot.saveSettings(value);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([bot, bot.session]),
    builder: (context, _) {
      final busy = bot.loading || bot.saving || bot.loadFailed;
      final ready = bot.session.status == RadioStatus.ready;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const Key('bot-mode-toggle'),
                title: const Text('Bot Mode'),
                subtitle: Text(
                  bot.enabled
                      ? 'ON · radio !${bot.armedRadio!.toRadixString(16).padLeft(8, '0')}'
                      : ready
                      ? 'OFF · enable for this connected radio'
                      : 'OFF · connect a radio to enable',
                ),
                value: bot.enabled,
                onChanged: busy || (!ready && !bot.enabled)
                    ? null
                    : bot.setEnabled,
              ),
              const Text(
                'Free, local and foreground only. Direct messages by default. '
                'Disconnecting or leaving the app turns Bot Mode off.',
              ),
              Text(
                'Away replies: ${bot.settings.autoReply ? 'on' : 'off'} · commands: ${bot.settings.commands ? 'on' : 'off'} · '
                'channel commands: ${bot.settings.channelCommands ? 'selected channels' : 'off'}',
              ),
              Text(
                'Sender cooldown: ${bot.settings.cooldownMinutes} min · 6 replies/hour maximum',
              ),
              if (bot.error != null)
                Text(
                  bot.error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              TextButton.icon(
                onPressed: busy ? null : () => _edit(context),
                icon: const Icon(Icons.tune),
                label: const Text('BOT SETTINGS'),
              ),
              if (bot.activities.isNotEmpty) ...[
                const Text('BOT ACTIVITY · latest 20 shown, 100 retained'),
                for (final activity in bot.activities.take(20))
                  ListTile(
                    dense: true,
                    title: Text('${activity.trigger} · ${activity.outcome}'),
                    subtitle: Text(
                      '${activity.time.toLocal()} · radio !${activity.radio.toRadixString(16).padLeft(8, '0')} · '
                      'sender !${activity.peer.toRadixString(16).padLeft(8, '0')} · channel ${activity.channel}',
                    ),
                  ),
                TextButton(
                  onPressed: busy ? null : bot.clearActivity,
                  child: const Text('CLEAR BOT ACTIVITY'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
