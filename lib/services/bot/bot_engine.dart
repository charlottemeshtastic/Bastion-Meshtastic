import 'dart:convert';
import '../../models/chat_message.dart';

class BotSettings {
  const BotSettings({
    this.reply = 'I’m away. Your message was received.',
    this.autoReply = true,
    this.commands = true,
    this.channelCommands = false,
    this.channels = const [],
    this.cooldownMinutes = 5,
  });
  static const prefix = '[Bastion bot] ';
  final String reply;
  final bool autoReply;
  final bool commands;
  final bool channelCommands;
  final List<int> channels;
  final int cooldownMinutes;

  String? get validationError {
    if (reply.trim().isEmpty ||
        utf8.encode('$prefix${reply.trim()}').length > 233) {
      return 'Reply plus the bot marker must fit 233 UTF-8 bytes (emoji use more bytes).';
    }
    if (cooldownMinutes < 1 || cooldownMinutes > 60) {
      return 'Cooldown must be 1–60 minutes.';
    }
    if (channels.length > 8 ||
        channels.any((c) => c < 0 || c > 7) ||
        channels.toSet().length != channels.length) {
      return 'Choose valid channel indices.';
    }
    if (channelCommands && (!commands || channels.isEmpty)) {
      return 'Enable commands and select at least one channel.';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'reply': reply.trim(),
    'autoReply': autoReply,
    'commands': commands,
    'channelCommands': channelCommands,
    'channels': channels,
    'cooldownMinutes': cooldownMinutes,
  };
  factory BotSettings.fromJson(Map<String, dynamic> json) => BotSettings(
    reply: json['reply'] as String,
    autoReply: json['autoReply'] as bool,
    commands: json['commands'] as bool,
    channelCommands: json['channelCommands'] as bool,
    channels: List<int>.from(json['channels'] as List),
    cooldownMinutes: json['cooldownMinutes'] as int,
  );
}

class BotDecision {
  const BotDecision(this.reason, {this.text, this.destination, this.command});
  final String reason;
  final String? text;
  final int? destination;
  final String? command;
  bool get replies => text != null;
}

/// Pure reply policy. Limits are reserved before Bluetooth writes, including
/// failed/unconfirmed writes. There are no delayed replies or automatic retries.
class BotEngine {
  final _seen = <String>{};
  final _peerLast = <String, DateTime>{};
  final _attempts = <({int radio, int peer, DateTime time})>[];
  List<Map<String, Object?>> get attemptsJson => _attempts
      .map(
        (a) => <String, Object?>{
          'radio': a.radio,
          'peer': a.peer,
          'time': a.time.toIso8601String(),
        },
      )
      .toList();
  DateTime? _lastAttempt;

  void restoreAttempt(int radio, int peer, DateTime time) {
    final key = '$radio:$peer';
    final previous = _peerLast[key];
    if (previous == null || previous.isBefore(time)) {
      _peerLast[key] = time;
    }
    _attempts.add((radio: radio, peer: peer, time: time));
    if (_lastAttempt == null || _lastAttempt!.isBefore(time)) {
      _lastAttempt = time;
    }
  }

  BotDecision evaluate(
    ChatMessage message,
    BotSettings settings, {
    required DateTime now,
    required bool enabled,
    required int? armedRadio,
    required bool ready,
    required bool channelEnabled,
    required int nodeCount,
  }) {
    if (message.outgoing || message.state != MessageState.received) {
      return const BotDecision('Outgoing/status event');
    }
    if (!_seen.add(message.key)) {
      return const BotDecision('Duplicate packet');
    }
    if (_seen.length > 1000) {
      _seen.remove(_seen.first);
    }
    if (!enabled || !ready || armedRadio != message.radio) {
      return const BotDecision('Bot paused');
    }
    if (settings.validationError != null || !channelEnabled) {
      return const BotDecision('Invalid settings or disabled channel');
    }
    if (message.from <= 0 ||
        message.from >= ChatMessage.broadcast ||
        message.from == message.radio ||
        message.packetId == 0 ||
        (message.to != message.radio && message.to != ChatMessage.broadcast)) {
      return const BotDecision('Invalid sender, destination or packet ID');
    }
    final age = now.difference(message.time);
    if (age > const Duration(minutes: 2) ||
        age < const Duration(seconds: -30)) {
      return const BotDecision('Stale or future-dated packet');
    }
    final text = message.text.trim();
    if (text.isEmpty || text.toLowerCase().contains('[bastion bot]')) {
      return const BotDecision('Empty message or bot marker');
    }
    final command = text.toLowerCase();
    final known = command == '!help' || command == '!status';
    if (!message.isDirect &&
        (!settings.channelCommands ||
            !settings.channels.contains(message.channel) ||
            !known)) {
      return const BotDecision(
        'Channel replies restricted to selected commands',
      );
    }
    String reply;
    String trigger;
    if (known) {
      if (!settings.commands) {
        return const BotDecision('Commands disabled');
      }
      trigger = command;
      reply = command == '!help'
          ? 'Commands: !help, !status. Automated replies; cooldown applies.'
          : 'Connected to !${message.radio.toRadixString(16).padLeft(8, '0')}; $nodeCount known nodes. Bot active while connected.';
    } else {
      // Unknown commands never receive an away reply, limiting bot interactions.
      if (text.startsWith('!') || !settings.autoReply) {
        return const BotDecision('Unknown command or auto-reply disabled');
      }
      trigger = 'Auto-reply';
      reply = settings.reply.trim();
    }
    _attempts.removeWhere(
      (t) => now.difference(t.time) >= const Duration(hours: 1),
    );
    _peerLast.removeWhere(
      (_, t) => now.difference(t) >= const Duration(hours: 1),
    );
    final previous = _peerLast['${message.radio}:${message.from}'];
    if (previous != null &&
        now.difference(previous) <
            Duration(minutes: settings.cooldownMinutes)) {
      return const BotDecision('Sender cooldown');
    }
    if (_lastAttempt != null &&
        now.difference(_lastAttempt!) < const Duration(seconds: 30)) {
      return const BotDecision('Global 30-second spacing');
    }
    if (_attempts.length >= 6) {
      return const BotDecision('Global limit: 6 replies per hour');
    }
    restoreAttempt(message.radio, message.from, now);
    return BotDecision(
      'Reply reserved',
      text: '${BotSettings.prefix}$reply',
      destination: message.isDirect ? message.from : ChatMessage.broadcast,
      command: trigger,
    );
  }
}
