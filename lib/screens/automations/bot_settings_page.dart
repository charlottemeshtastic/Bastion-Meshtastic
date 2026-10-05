import 'package:flutter/material.dart';
import '../../services/bot/bot_engine.dart';

class BotSettingsPage extends StatefulWidget {
  const BotSettingsPage({
    super.key,
    required this.settings,
    required this.channels,
  });
  final BotSettings settings;
  final List<int> channels;
  @override
  State<BotSettingsPage> createState() => _BotSettingsPageState();
}

class _BotSettingsPageState extends State<BotSettingsPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _reply;
  late final TextEditingController _cooldown;
  late bool _autoReply;
  late bool _commands;
  late bool _channelCommands;
  late Set<int> _channels;
  @override
  void initState() {
    super.initState();
    _reply = TextEditingController(text: widget.settings.reply);
    _cooldown = TextEditingController(
      text: '${widget.settings.cooldownMinutes}',
    );
    _autoReply = widget.settings.autoReply;
    _commands = widget.settings.commands;
    _channelCommands = widget.settings.channelCommands;
    _channels = widget.settings.channels.toSet();
  }

  BotSettings get _value => BotSettings(
    reply: _reply.text.trim(),
    autoReply: _autoReply,
    commands: _commands,
    channelCommands: _channelCommands,
    channels: _channels.toList()..sort(),
    cooldownMinutes: int.tryParse(_cooldown.text) ?? 0,
  );
  @override
  void dispose() {
    _reply.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BOT SETTINGS')),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: FilledButton.icon(
        icon: const Icon(Icons.save_outlined),
        label: const Text('SAVE BOT SETTINGS'),
        onPressed: () {
          if (!_form.currentState!.validate()) {
            return;
          }
          final error = _value.validationError;
          if (error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
            return;
          }
          Navigator.pop(context, _value);
        },
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Saving settings turns Bot Mode off. Review your choices, then enable it on AUTO.',
          ),
          SwitchListTile(
            title: const Text('Away reply to direct messages'),
            subtitle: const Text(
              'Normal messages addressed to your radio only',
            ),
            value: _autoReply,
            onChanged: (v) => setState(() => _autoReply = v),
          ),
          TextFormField(
            controller: _reply,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Custom away reply',
              helperText:
                  'Every reply includes [Bastion bot]; total limit 233 UTF-8 bytes.',
            ),
            validator: (_) => BotSettings(
              reply: _reply.text,
              cooldownMinutes: 5,
            ).validationError,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Enable !help and !status'),
            subtitle: const Text(
              'Status shares your radio ID and known-node count; no coordinates or message text',
            ),
            value: _commands,
            onChanged: (v) => setState(() {
              _commands = v;
              if (!v) {
                _channelCommands = false;
              }
            }),
          ),
          SwitchListTile(
            title: const Text('Reply to channel commands'),
            subtitle: const Text(
              'Replies are broadcast on selected channels. Ordinary channel messages never trigger away replies.',
            ),
            value: _channelCommands,
            onChanged: !_commands
                ? null
                : (v) => setState(() => _channelCommands = v),
          ),
          if (_channelCommands) ...[
            const Text(
              'Select channel indices. Only currently enabled radio channels can transmit.',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final index in {
                  ...widget.channels,
                  ..._channels,
                }.toList()..sort())
                  FilterChip(
                    label: Text('Channel $index'),
                    selected: _channels.contains(index),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _channels.add(index);
                      } else {
                        _channels.remove(index);
                      }
                    }),
                  ),
              ],
            ),
            if (widget.channels.isEmpty)
              const Text('Connect a radio to choose channels.'),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _cooldown,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Sender cooldown (minutes)',
              helperText:
                  '1–60 minutes; shared across channels for each sender',
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n < 1 || n > 60
                  ? 'Enter 1–60 minutes.'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Always enforced: 30 seconds between replies and at most 6 replies per hour across all radios. '
            'Failed writes also consume the limit. Limits survive restart and clearing the log. '
            'Bot-marked messages, outgoing echoes, duplicates, stale packets and unknown commands are ignored. '
            'These safeguards reduce loops with other bots; they cannot identify every third-party bot.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Foreground only. Bot turns off on disconnect, backgrounding or app restart. '
            'No queued replies, automatic retries, AI service or subscription.',
          ),
        ],
      ),
    ),
  );
}
