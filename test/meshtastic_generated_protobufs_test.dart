import 'dart:typed_data';

import 'package:bastion/generated/meshtastic/admin.pb.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/generated/meshtastic/mesh.pb.dart';
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/services/meshtastic_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Same wire bytes as meshtastic_routing_ack_test.dart.
  final routingAck = Uint8List.fromList([
    0x0d, 0x34, 0x12, 0x00, 0x00,
    0x22, 0x0b,
    0x08, 0x05,
    0x12, 0x02, 0x18, 0x01,
    0x35, 0x2a, 0x00, 0x00, 0x00,
  ]);

  test('generated MeshPacket decodes routing ACK like the hand codec', () {
    final packet = MeshPacket.fromBuffer(routingAck);
    final routing = Routing.fromBuffer(packet.decoded.payload);
    final hand = MeshtasticTextCodec.decodeRoutingAck(routingAck)!;

    expect(packet.from, hand.from);
    expect(packet.decoded.portnum, PortNum.ROUTING_APP);
    expect(packet.decoded.requestId, hand.requestId);
    expect(routing.errorReason.value, hand.errorReason);
  });

  test('generated AdminMessage set_config round-trips LoRa settings', () {
    final admin = AdminMessage(
      setConfig: Config(
        lora: Config_LoRaConfig(
          region: Config_LoRaConfig_RegionCode.US,
          modemPreset: Config_LoRaConfig_ModemPreset.LONG_FAST,
          hopLimit: 3,
          usePreset: true,
        ),
      ),
    );
    final decoded = AdminMessage.fromBuffer(admin.writeToBuffer());
    expect(decoded.whichPayloadVariant(), AdminMessage_PayloadVariant.setConfig);
    expect(decoded.setConfig.lora.region, Config_LoRaConfig_RegionCode.US);
    expect(decoded.setConfig.lora.hopLimit, 3);
  });
}
