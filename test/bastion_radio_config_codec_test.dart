import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_radio_config_codec.dart';

void main() {
  test('reads LoRa region preset and hop limit', () {
    // Config.lora (6) containing region (7), preset (2), hop_limit (8).
    final config = Uint8List.fromList([0x32, 0x06, 0x38, 0x01, 0x10, 0x03, 0x40, 0x05]);
    expect(BastionRadioConfigCodec.loraSummary(config),
        'Region: 1 • Preset: 3 • Hop limit: 5');
  });

  test('reads channel name and role without exposing PSK', () {
    // Channel.index (1), settings (2), role (3); settings.psk (2), name (3).
    final channel = Uint8List.fromList([
      0x08, 0x00, 0x12, 0x0b, 0x12, 0x03, 0x01, 0x02, 0x03,
      0x1a, 0x04, 0x54, 0x45, 0x53, 0x54, 0x18, 0x01,
    ]);
    expect(BastionRadioConfigCodec.channelSummary(channel),
        'Channel 0 • Primary • TEST');
  });

  test('decodes safe channel metadata without returning a PSK', () {
    final channel = Uint8List.fromList([
      0x08, 0x01, 0x12, 0x0b, 0x12, 0x03, 0x01, 0x02, 0x03,
      0x1a, 0x04, 0x54, 0x45, 0x53, 0x54, 0x18, 0x02,
    ]);
    final metadata = BastionRadioConfigCodec.channelMetadata(channel);
    expect(metadata.index, 1);
    expect(metadata.role, 2);
    expect(metadata.name, 'TEST');
  });

  test('rejects channel metadata with invalid slot', () {
    final channel = Uint8List.fromList([
      0x08, 0x09, 0x12, 0x00, 0x18, 0x02,
    ]);
    expect(() => BastionRadioConfigCodec.channelMetadata(channel),
        throwsFormatException);
  });

  test('rejects truncated protobuf', () {
    expect(() => BastionRadioConfigCodec.fields(Uint8List.fromList([0x12, 0x05, 0x01])),
        throwsFormatException);
  });
}
