import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_admin_packet_codec.dart';

void main() {
  test('wraps admin message in local ADMIN_APP packet with acknowledgement', () {
    final result = BastionAdminPacketCodec.toRadio(
      adminMessage: Uint8List.fromList([0x82, 0x02, 0x01, 0x01]),
      localNode: 0x12345678,
      packetId: 42,
    );
    expect(result, [
      0x0a, 0x16,
      0x15, 0x78, 0x56, 0x34, 0x12,
      0x22, 0x08, 0x08, 0x06, 0x12, 0x04, 0x82, 0x02, 0x01, 0x01,
      0x35, 0x2a, 0, 0, 0,
      0x50, 0x01,
    ]);
  });

  test('refuses empty payloads and invalid node or packet IDs', () {
    final payload = Uint8List.fromList([1]);
    expect(() => BastionAdminPacketCodec.toRadio(
      adminMessage: Uint8List(0), localNode: 1, packetId: 1,
    ), throwsArgumentError);
    expect(() => BastionAdminPacketCodec.toRadio(
      adminMessage: payload, localNode: 0, packetId: 1,
    ), throwsRangeError);
    expect(() => BastionAdminPacketCodec.toRadio(
      adminMessage: payload, localNode: 1, packetId: 0,
    ), throwsRangeError);
  });
}
