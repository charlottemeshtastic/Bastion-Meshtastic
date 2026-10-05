import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion_meshtastic/generated/meshtastic/channel.pb.dart';
import 'package:bastion_meshtastic/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion_meshtastic/models/chat_message.dart';
import 'package:bastion_meshtastic/services/bot/bot_controller.dart';
import 'package:bastion_meshtastic/services/bot/bot_engine.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'messaging_test.dart' show WriteTransport;

void main() {
  late RadioSession session;
  late WriteTransport transport;
  late BotController bot;
  late DateTime now;
  var incomingId = 200;
  var outgoingId = 100;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 5, 12);
    incomingId = 200;
    outgoingId = 100;
    session = RadioSession(
      clock: () => now,
      nonce: () => 123,
      packetId: () => ++outgoingId,
    );
    transport = WriteTransport();
    bot = BotController(session, clock: () => now);
    await bot.load();
    await session.connect(transport);
    transport.emit(pb.FromRadio(myInfo: pb.MyNodeInfo(myNodeNum: 42)));
    transport.emit(
      pb.FromRadio(channel: Channel(index: 0, role: Channel_Role.PRIMARY)),
    );
    transport.emit(pb.FromRadio(configCompleteId: 123));
  });
  tearDown(() async {
    await bot.sendComplete;
    await bot.saved;
    bot.dispose();
    await session.disconnect();
    session.dispose();
    await transport.finish();
  });
  void incoming({String text = 'hello', int peer = 7, int to = 42, int? id}) =>
      transport.emit(
        pb.FromRadio(
          packet: pb.MeshPacket(
            from: peer,
            to: to,
            id: id ?? ++incomingId,
            rxTime: now.millisecondsSinceEpoch ~/ 1000,
            channel: 0,
            decoded: pb.Data(
              portnum: PortNum.TEXT_MESSAGE_APP,
              payload: utf8.encode(text),
            ),
          ),
        ),
      );
  List<pb.MeshPacket> sends() => transport.writes
      .map(pb.ToRadio.fromBuffer)
      .where((f) => f.hasPacket())
      .map((f) => f.packet)
      .toList();

  test(
    'defaults off, explicit toggle sends once and tracks real ACK status',
    () async {
      incoming();
      expect(sends(), isEmpty);
      bot.setEnabled(true);
      incoming(text: '!help');
      await bot.sendComplete;
      expect(sends(), hasLength(1));
      expect(sends().single.to, 7);
      expect(bot.activities.first.outcome, contains('Written to radio'));
      transport.emit(
        pb.FromRadio(
          packet: pb.MeshPacket(
            from: 7,
            to: 42,
            decoded: pb.Data(
              portnum: PortNum.ROUTING_APP,
              requestId: sends().single.id,
              payload: pb.Routing(
                errorReason: pb.Routing_Error.NONE,
              ).writeToBuffer(),
            ),
          ),
        ),
      );
      expect(
        bot.activities.first.outcome,
        'Mesh acknowledged · not a read receipt',
      );
      incoming();
      expect(sends(), hasLength(1));
      expect(bot.activities.first.outcome, contains('cooldown'));
    },
  );
  test(
    'settings/log persist but restart stays off; clearing log preserves rate limits',
    () async {
      await bot.saveSettings(
        const BotSettings(reply: 'BCS is away.', cooldownMinutes: 10),
      );
      bot.setEnabled(true);
      incoming();
      await bot.sendComplete;
      await bot.saved;
      await bot.clearActivity();
      expect(bot.activities, isEmpty);
      bot.dispose();
      bot = BotController(session, clock: () => now);
      await bot.load();
      expect(bot.enabled, isFalse);
      expect(bot.settings.reply, 'BCS is away.');
      bot.setEnabled(true);
      now = now.add(const Duration(minutes: 1));
      incoming();
      expect(sends(), hasLength(1));
      expect(bot.activities.first.outcome, contains('cooldown'));
    },
  );
  test('disconnect disarms and reconnect does not re-enable', () async {
    bot.setEnabled(true);
    await session.disconnect();
    expect(bot.enabled, isFalse);
    expect(bot.armedRadio, isNull);
    bot.setEnabled(true);
    expect(bot.enabled, isFalse);
    expect(bot.error, contains('Connect a radio'));
  });
  test(
    'write failure logged honestly, cooldown retained and no retry',
    () async {
      transport.reject = true;
      bot.setEnabled(true);
      incoming();
      await bot.sendComplete;
      expect(sends(), isEmpty);
      expect(bot.activities.first.outcome, 'Delivery unconfirmed');
      transport.reject = false;
      now = now.add(const Duration(minutes: 1));
      incoming();
      expect(sends(), isEmpty);
      expect(bot.activities.first.outcome, contains('cooldown'));
    },
  );
  test('editing disarms, invalid edit does not replace settings', () async {
    bot.setEnabled(true);
    expect(await bot.saveSettings(const BotSettings(reply: ' ')), isFalse);
    expect(bot.settings.reply, isNot(' '));
    expect(
      await bot.saveSettings(const BotSettings(reply: 'New away message')),
      isTrue,
    );
    expect(bot.enabled, isFalse);
  });
  test('channel commands opt-in and bot marker never triggers', () async {
    bot.setEnabled(true);
    incoming(to: ChatMessage.broadcast, text: '!help');
    expect(sends(), isEmpty);
    await bot.saveSettings(
      const BotSettings(channelCommands: true, channels: [0]),
    );
    bot.setEnabled(true);
    incoming(to: ChatMessage.broadcast, text: '!help');
    await bot.sendComplete;
    expect(sends().single.to, ChatMessage.broadcast);
    now = now.add(const Duration(minutes: 6));
    incoming(text: '[Bastion bot] !help');
    expect(sends(), hasLength(1));
  });
  test('OFF between receive callback and write cancels the reply', () async {
    bot.setEnabled(true);
    incoming();
    bot.setEnabled(false);
    await bot.sendComplete;
    expect(sends(), isEmpty);
    expect(
      bot.activities.first.outcome,
      'Cancelled before radio write · bot paused',
    );
  });
  test('malformed saved data remains intact and cannot enable', () async {
    bot.dispose();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(BotController.storageKey, '{broken');
    bot = BotController(session, clock: () => now);
    await bot.load();
    expect(bot.loadFailed, isTrue);
    bot.setEnabled(true);
    expect(bot.enabled, isFalse);
    expect(await bot.saveSettings(const BotSettings()), isFalse);
    expect(prefs.getString(BotController.storageKey), '{broken');
  });
}
