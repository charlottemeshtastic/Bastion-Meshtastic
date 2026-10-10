import 'package:bastion/services/bastion_background_service.dart';
import 'package:bastion/services/bastion_message_alerts.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:bastion/services/meshtastic_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoKeeper implements BastionBackgroundKeeper {
  @override
  Future<void> keepAlive({required String radioName, required bool reconnecting}) async {}
  @override
  Future<void> release() async {}
}

class _RecordingAlerts implements BastionMessageAlerts {
  final shown = <String>[];

  @override
  Future<void> show({
    required int packetId,
    required String sender,
    required String text,
    required bool isDirect,
    required int channel,
  }) async =>
      shown.add('${isDirect ? 'DM' : 'ch$channel'} $sender: $text');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAlerts alerts;
  late MeshtasticRadioCoordinator radio;

  setUp(() {
    alerts = _RecordingAlerts();
    radio = MeshtasticRadioCoordinator(background: _NoKeeper(), alerts: alerts);
  });

  tearDown(() => radio.dispose());

  MeshtasticTextMessage message({required int to, int channel = 0}) => MeshtasticTextMessage(
        packetId: 5,
        from: 0xabcdef01,
        to: to,
        channel: channel,
        text: 'Camp at the ridge',
      );

  test('stays quiet while the app is in the foreground', () {
    radio.inForeground = true;
    radio.alertIncomingForTest(message(to: 0x1234));
    expect(alerts.shown, isEmpty);
  });

  test('notifies direct and channel messages in the background', () {
    radio.inForeground = false;
    radio.alertIncomingForTest(message(to: 0x1234));
    radio.alertIncomingForTest(message(to: MeshtasticTextCodec.broadcastNode, channel: 2));
    expect(alerts.shown, [
      'DM !abcdef01: Camp at the ridge',
      'ch2 !abcdef01: Camp at the ridge',
    ]);
  });

  test('local alerts are a no-op off Android', () async {
    await BastionLocalMessageAlerts().show(
      packetId: 1, sender: 'A', text: 'b', isDirect: true, channel: 0);
  });
}
