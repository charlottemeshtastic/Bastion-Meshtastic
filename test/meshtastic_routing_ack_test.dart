import 'dart:typed_data';

import 'package:bastion/services/meshtastic_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // MeshPacket.from fixed32 = 0x1234, decoded Data with ROUTING_APP (5),
  // Routing.error_reason = NONE (0), Data.request_id = 42 (fixed32).
  test('decodes a correlated successful routing acknowledgement', () {
    final packet = Uint8List.fromList([
      0x0d, 0x34, 0x12, 0x00, 0x00,
      0x22, 0x0b,
      0x08, 0x05,
      0x12, 0x02, 0x18, 0x00,
      0x35, 0x2a, 0x00, 0x00, 0x00,
    ]);
    final ack = MeshtasticTextCodec.decodeRoutingAck(packet);
    expect(ack?.requestId, 42);
    expect(ack?.from, 0x1234);
    expect(ack?.errorReason, 0);
  });

  test('decodes routing failure without treating it as delivered', () {
    final packet = Uint8List.fromList([
      0x0d, 0x34, 0x12, 0x00, 0x00,
      0x22, 0x0b,
      0x08, 0x05,
      0x12, 0x02, 0x18, 0x01,
      0x35, 0x2a, 0x00, 0x00, 0x00,
    ]);
    expect(MeshtasticTextCodec.decodeRoutingAck(packet)?.errorReason, 1);
  });

  test('ignores routing responses with no correlated request id', () {
    final packet = Uint8List.fromList([
      0x22, 0x06, 0x08, 0x05, 0x12, 0x02, 0x18, 0x00,
    ]);
    expect(MeshtasticTextCodec.decodeRoutingAck(packet), isNull);
  });
}
