import 'dart:convert';
import 'dart:typed_data';

import 'package:bastion/services/meshtastic_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes an incoming channel text MeshPacket', () {
    final data = <int>[0x08, 0x01, 0x12, 0x02, ...utf8.encode('hi')];
    final packet = Uint8List.fromList([
      0x0d, 0x44, 0x33, 0x22, 0x11,
      0x15, 0xff, 0xff, 0xff, 0xff,
      0x18, 0x02,
      0x22, data.length, ...data,
      0x35, 0x04, 0x03, 0x02, 0x01,
      0x3d, 0x10, 0x00, 0x00, 0x00,
    ]);

    final message = MeshtasticTextCodec.decodeMeshPacket(packet);
    expect(message, isNotNull);
    expect(message!.from, 0x11223344);
    expect(message.to, MeshtasticTextCodec.broadcastNode);
    expect(message.channel, 2);
    expect(message.packetId, 0x01020304);
    expect(message.rxTime, 16);
    expect(message.text, 'hi');
    expect(message.isBroadcast, isTrue);
  });

  test('ignores non-text Data payloads', () {
    final data = <int>[0x08, 0x03, 0x12, 0x01, 0x01];
    final packet = Uint8List.fromList([0x22, data.length, ...data]);
    expect(MeshtasticTextCodec.decodeMeshPacket(packet), isNull);
  });

  test('encodes a broadcast text message as ToRadio packet', () {
    final bytes = MeshtasticTextCodec.toRadioText(
      text: 'hi',
      destination: MeshtasticTextCodec.broadcastNode,
      packetId: 0x01020304,
    );
    expect(bytes, Uint8List.fromList([
      0x0a, 0x12,
      0x15, 0xff, 0xff, 0xff, 0xff,
      0x22, 0x06, 0x08, 0x01, 0x12, 0x02, 0x68, 0x69,
      0x35, 0x04, 0x03, 0x02, 0x01,
    ]));
  });

  test('direct text requests an ack when requested', () {
    final bytes = MeshtasticTextCodec.toRadioText(
      text: 'ok',
      destination: 0x11223344,
      packetId: 7,
      wantAck: true,
    );
    expect(bytes.sublist(bytes.length - 2), [0x50, 0x01]);
  });
}
