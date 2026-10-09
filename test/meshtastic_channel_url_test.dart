import 'package:bastion/generated/meshtastic/apponly.pb.dart';
import 'package:bastion/generated/meshtastic/channel.pb.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/services/meshtastic_channel_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final set = ChannelSet(
    settings: [
      ChannelSettings(psk: [1]),
      ChannelSettings(name: 'Trail', psk: List.generate(32, (i) => i)),
    ],
    loraConfig: Config_LoRaConfig(
      region: Config_LoRaConfig_RegionCode.US,
      modemPreset: Config_LoRaConfig_ModemPreset.LONG_FAST,
      usePreset: true,
      hopLimit: 3,
    ),
  );

  test('round-trips through an unpadded base64url link', () {
    final link = MeshtasticChannelUrl.encode(set);
    expect(link, startsWith('https://meshtastic.org/e/#'));
    expect(link, isNot(contains('=')));
    expect(link, isNot(contains('+')));
    expect(MeshtasticChannelUrl.decode(link), set);
  });

  test('accepts add links, bare fragments and standard base64', () {
    final fragment = MeshtasticChannelUrl.encode(set).split('#').last;
    expect(MeshtasticChannelUrl.decode('https://meshtastic.org/e/?add=true#$fragment'), set);
    expect(MeshtasticChannelUrl.isAddLink('https://meshtastic.org/e/?add=true#$fragment'), isTrue);
    expect(MeshtasticChannelUrl.decode('  $fragment\n'), set);
    final standard = fragment.replaceAll('-', '+').replaceAll('_', '/');
    expect(MeshtasticChannelUrl.decode(standard), set);
  });

  test('decodes the official default-channel link', () {
    final decoded = MeshtasticChannelUrl.decode('https://meshtastic.org/e/#CgMSAQESBggBQANIAQ');
    expect(decoded.settings.single.psk, [1]);
    expect(decoded.settings.single.name, isEmpty);
    expect(decoded.loraConfig.usePreset, isTrue);
    expect(decoded.loraConfig.hopLimit, 3);
    expect(decoded.loraConfig.txEnabled, isTrue);
  });

  test('rejects empty, garbage and channel-less links', () {
    expect(() => MeshtasticChannelUrl.decode('https://meshtastic.org/e/#'), throwsFormatException);
    expect(() => MeshtasticChannelUrl.decode('https://meshtastic.org/e/#!!!'), throwsFormatException);
    final empty = MeshtasticChannelUrl.encode(ChannelSet(loraConfig: Config_LoRaConfig(hopLimit: 3)));
    expect(() => MeshtasticChannelUrl.decode(empty), throwsFormatException);
  });
}
