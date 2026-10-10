import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_admin_codec.dart';

void main() {
  test('encodes owner, channel, config and module admin field tags', () {
    final data = Uint8List.fromList([8, 1]);
    expect(BastionAdminCodec.setOwner(data), [0x82, 0x02, 2, 8, 1]);
    expect(BastionAdminCodec.setChannel(data), [0x8a, 0x02, 2, 8, 1]);
    expect(BastionAdminCodec.setConfig(data), [0x92, 0x02, 2, 8, 1]);
    expect(BastionAdminCodec.setModuleConfig(data), [0x9a, 0x02, 2, 8, 1]);
  });
  test('appends session passkey using admin field 101', () {
    final result = BastionAdminCodec.withSessionPasskey(
      BastionAdminCodec.setOwner(Uint8List.fromList([8, 1])),
      Uint8List.fromList([7, 9]),
    );
    expect(result, [0x82, 0x02, 2, 8, 1, 0xaa, 0x06, 2, 7, 9]);
  });
  test('rejects empty admin payload and empty session passkey', () {
    expect(() => BastionAdminCodec.setConfig(Uint8List(0)), throwsArgumentError);
    expect(() => BastionAdminCodec.withSessionPasskey(Uint8List.fromList([1]), Uint8List(0)), throwsArgumentError);
  });
}
