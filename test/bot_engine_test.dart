import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/models/chat_message.dart';
import 'package:bastion_meshtastic/services/bot/bot_engine.dart';

void main() {
  final start = DateTime.utc(2026, 10, 5, 12);
  var counter = 0;
  ChatMessage message({
    int peer = 7,
    int radio = 42,
    int? to,
    String text = 'hello',
    int channel = 0,
    int? id,
    DateTime? time,
    bool outgoing = false,
  }) {
    final packet = id ?? ++counter;
    return ChatMessage(
      key: '$radio:$peer:$packet',
      radio: radio,
      packetId: packet,
      from: peer,
      to: to ?? radio,
      channel: channel,
      text: text,
      time: time ?? start,
      outgoing: outgoing,
      state: outgoing ? MessageState.writing : MessageState.received,
    );
  }

  BotDecision evaluate(
    BotEngine engine,
    ChatMessage m, {
    BotSettings settings = const BotSettings(),
    DateTime? now,
    bool enabled = true,
    bool ready = true,
    bool channelEnabled = true,
    int? armedRadio = 42,
  }) => engine.evaluate(
    m,
    settings,
    now: now ?? start,
    enabled: enabled,
    ready: ready,
    channelEnabled: channelEnabled,
    armedRadio: armedRadio,
    nodeCount: 3,
  );

  test('off, disconnected, wrong radio and disabled channels never reply', () {
    final engine = BotEngine();
    expect(evaluate(engine, message(), enabled: false).replies, isFalse);
    expect(evaluate(engine, message(), ready: false).replies, isFalse);
    expect(evaluate(engine, message(radio: 99)).replies, isFalse);
    expect(evaluate(engine, message(), channelEnabled: false).replies, isFalse);
    expect(evaluate(engine, message()).replies, isTrue);
  });
  test('direct away replies carry bot marker and target sender', () {
    final d = evaluate(BotEngine(), message());
    expect(d.text, '${BotSettings.prefix}I’m away. Your message was received.');
    expect(d.destination, 7);
    expect(d.command, 'Auto-reply');
  });
  test(
    'ordinary channel messages never reply, selected commands require opt-in',
    () {
      expect(
        evaluate(
          BotEngine(),
          message(to: ChatMessage.broadcast, text: '!help'),
        ).replies,
        isFalse,
      );
      const settings = BotSettings(channelCommands: true, channels: [1]);
      expect(
        evaluate(
          BotEngine(),
          message(to: ChatMessage.broadcast, channel: 1),
          settings: settings,
        ).replies,
        isFalse,
      );
      expect(
        evaluate(
          BotEngine(),
          message(to: ChatMessage.broadcast, text: '!help'),
          settings: settings,
        ).replies,
        isFalse,
      );
      final d = evaluate(
        BotEngine(),
        message(to: ChatMessage.broadcast, channel: 1, text: ' !HELP '),
        settings: settings,
      );
      expect(d.text, contains('!status'));
      expect(d.destination, ChatMessage.broadcast);
    },
  );
  test('commands return bounded non-sensitive status and can be disabled', () {
    final d = evaluate(BotEngine(), message(text: '!status'));
    expect(d.text, contains('!0000002a; 3 known nodes'));
    expect(d.text, isNot(contains('battery')));
    expect(
      evaluate(
        BotEngine(),
        message(text: '!help'),
        settings: const BotSettings(commands: false),
      ).replies,
      isFalse,
    );
    expect(
      evaluate(
        BotEngine(),
        message(),
        settings: const BotSettings(autoReply: false),
      ).replies,
      isFalse,
    );
    expect(evaluate(BotEngine(), message(text: '!unknown')).replies, isFalse);
  });
  test(
    'markers, echoes, stale packets, future packets and invalid IDs ignored',
    () {
      final e = BotEngine();
      for (final m in [
        message(text: '[BASTION BOT] reply'),
        message(outgoing: true),
        message(time: start.subtract(const Duration(minutes: 3))),
        message(time: start.add(const Duration(minutes: 1))),
        message(id: 0),
        message(peer: 42),
        message(peer: 0),
        message(to: 8),
      ]) {
        expect(evaluate(e, m).replies, isFalse);
      }
      expect(evaluate(e, message()).replies, isTrue);
    },
  );
  test('duplicate packets cannot retrigger even after cooldown', () {
    final e = BotEngine();
    final m = message();
    expect(evaluate(e, m).replies, isTrue);
    expect(
      evaluate(e, m, now: start.add(const Duration(minutes: 6))).reason,
      'Duplicate packet',
    );
  });
  test('sender cooldown spans channels, global spacing spans radios', () {
    final e = BotEngine();
    expect(evaluate(e, message()).replies, isTrue);
    expect(
      evaluate(
        e,
        message(peer: 8),
        now: start.add(const Duration(seconds: 10)),
      ).reason,
      'Global 30-second spacing',
    );
    expect(
      evaluate(
        e,
        message(channel: 1),
        now: start.add(const Duration(minutes: 1)),
      ).reason,
      'Sender cooldown',
    );
    final next = start.add(const Duration(minutes: 5));
    expect(evaluate(e, message(time: next), now: next).replies, isTrue);
  });
  test(
    'six reserved attempts per rolling hour and persisted attempts enforce limits',
    () {
      final e = BotEngine();
      for (var i = 0; i < 6; i++) {
        final now = start.add(Duration(minutes: i));
        expect(
          evaluate(
            e,
            message(peer: 7 + i, time: now),
            now: now,
          ).replies,
          isTrue,
        );
      }
      final restored = BotEngine();
      for (final a in e.attemptsJson) {
        restored.restoreAttempt(
          a['radio'] as int,
          a['peer'] as int,
          DateTime.parse(a['time'] as String),
        );
      }
      final now = start.add(const Duration(minutes: 7));
      expect(
        evaluate(restored, message(peer: 50, time: now), now: now).reason,
        'Global limit: 6 replies per hour',
      );
      final later = start.add(const Duration(hours: 1));
      expect(
        evaluate(restored, message(peer: 50, time: later), now: later).replies,
        isTrue,
      );
    },
  );
  test(
    'settings validate UTF-8 budget, cooldown and explicit channel selection',
    () {
      expect(const BotSettings(reply: '😀😀').validationError, isNull);
      expect(BotSettings(reply: '😀' * 55).validationError, isNotNull);
      expect(const BotSettings(reply: ' ').validationError, isNotNull);
      expect(const BotSettings(cooldownMinutes: 0).validationError, isNotNull);
      expect(
        const BotSettings(channelCommands: true).validationError,
        isNotNull,
      );
      expect(
        const BotSettings(
          channelCommands: true,
          channels: [0, 0],
        ).validationError,
        isNotNull,
      );
      const settings = BotSettings(
        reply: 'BackCountrySignal is away.',
        channelCommands: true,
        channels: [0],
        cooldownMinutes: 10,
      );
      final restored = BotSettings.fromJson(settings.toJson());
      expect(restored.toJson(), settings.toJson());
      expect(restored.validationError, isNull);
    },
  );
}
