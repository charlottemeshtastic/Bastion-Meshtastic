import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';

void main() {
  test('ChannelSettings name uses field 2, not PSK field 1', () {
    // Channel index=1; settings {psk=[1,2,3], name='FIELD'}.
    final channel = Uint8List.fromList([
      0x08, 0x01, 0x12, 0x0e,
      0x0a, 0x03, 0x01, 0x02, 0x03,
      0x12, 0x05, 0x46, 0x49, 0x45, 0x4c, 0x44,
      0x18, 0x01,
    ]);
    expect(readChannelName(channel), (1, 'FIELD'));
  });

  test('Channel with no name uses a safe fallback', () {
    expect(readChannelName(Uint8List.fromList([
      0x08, 0x00, 0x12, 0x02, 0x0a, 0x00,
    ])), (0, 'Channel 0'));
  });

  test('Malformed channel data is rejected', () {
    expect(() => readChannelName(Uint8List.fromList([0x12, 0x08, 0x01])),
        throwsFormatException);
  });
}
