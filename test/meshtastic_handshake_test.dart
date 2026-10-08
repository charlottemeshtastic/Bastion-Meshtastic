import 'dart:async';
import 'dart:typed_data';

import 'package:bastion/services/meshtastic_connection_controller.dart';
import 'package:bastion/services/meshtastic_handshake.dart';
import 'package:bastion/services/meshtastic_phoneapi_codec.dart';
import 'package:bastion/services/meshtastic_radio_session.dart';
import 'package:bastion/services/meshtastic_radio_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class HandshakeTransport implements MeshtasticRadioTransport {
  final inbound = StreamController<Uint8List>.broadcast();
  final sent = <Uint8List>[];
  bool connected = false;

  @override
  Stream<Uint8List> get fromRadio => inbound.stream;
  @override
  bool get isConnected => connected;
  @override
  Future<void> connect() async => connected = true;
  @override
  Future<void> disconnect() async => connected = false;

  @override
  Future<void> sendToRadio(Uint8List envelope) async {
    sent.add(envelope);
    if (envelope.length >= 2 && envelope.first == 0x18) {
      final id = _decodeVarint(envelope, 1);
      scheduleMicrotask(() {
        inbound.add(Uint8List.fromList([0x38, ..._encodeVarint(id)]));
      });
    }
  }
}

int _decodeVarint(Uint8List bytes, int offset) {
  var value = 0;
  var shift = 0;
  while (offset < bytes.length) {
    final byte = bytes[offset++];
    value |= (byte & 0x7f) << shift;
    if ((byte & 0x80) == 0) return value;
    shift += 7;
  }
  throw StateError('bad varint');
}

List<int> _encodeVarint(int value) {
  final out = <int>[];
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) byte |= 0x80;
    out.add(byte);
  } while (remaining != 0);
  return out;
}

void main() {
  test('PhoneAPI codec encodes config request and decodes completion', () {
    expect(
      MeshtasticPhoneApiCodec.wantConfig(69420),
      orderedEquals([0x18, 0xac, 0x9e, 0x04]),
    );

    final decoded = MeshtasticPhoneApiCodec.decodeFromRadio(
      Uint8List.fromList([0x08, 0x09, 0x38, 0xad, 0x9e, 0x04]),
    );
    expect(decoded.id, 9);
    expect(decoded.kind, FromRadioPayloadKind.configCompleteId);
    expect(decoded.configCompleteId, 69421);
  });

  test('two-stage handshake reaches ready state', () async {
    final transport = HandshakeTransport();
    final connection = MeshtasticConnectionController();
    final session = MeshtasticRadioSession(
      transport: transport,
      connection: connection,
    );
    await session.connect(deviceName: 'Bastion Test Radio');

    final handshake = MeshtasticHandshake(
      session: session,
      connection: connection,
      settleDelay: Duration.zero,
      timeout: const Duration(seconds: 1),
    );
    await handshake.synchronize();

    expect(connection.state, MeshtasticConnectionState.ready);
    expect(transport.sent.length, 3);
    expect(transport.sent.first,
        orderedEquals(MeshtasticPhoneApiCodec.wantConfig(69420)));
    expect(transport.sent.last,
        orderedEquals(MeshtasticPhoneApiCodec.wantConfig(69421)));

    await handshake.dispose();
    await session.dispose();
    await transport.inbound.close();
  });

  test('codec decodes local node number from MyNodeInfo', () {
    final nodeNum = MeshtasticPhoneApiCodec.decodeMyNodeNum(
      Uint8List.fromList([0x08, 0x96, 0x01]),
    );
    expect(nodeNum, 150);
  });

  test('codec recognizes rebooted signal', () {
    final decoded = MeshtasticPhoneApiCodec.decodeFromRadio(
      Uint8List.fromList([0x40, 0x01]),
    );
    expect(decoded.rebooted, isTrue);
  });
}
