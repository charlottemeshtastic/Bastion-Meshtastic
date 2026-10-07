import 'dart:async';
import 'dart:typed_data';

import 'package:bastion_meshtastic/services/meshtastic_connection_controller.dart';
import 'package:bastion_meshtastic/services/meshtastic_radio_session.dart';
import 'package:bastion_meshtastic/services/meshtastic_radio_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRadioTransport implements MeshtasticRadioTransport {
  final controller = StreamController<Uint8List>.broadcast();
  final sent = <Uint8List>[];
  bool connected = false;

  @override
  Stream<Uint8List> get fromRadio => controller.stream;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<void> disconnect() async => connected = false;

  @override
  Future<void> sendToRadio(Uint8List envelope) async => sent.add(envelope);
}

void main() {
  test('session connects, forwards envelopes, sends and disconnects', () async {
    final transport = FakeRadioTransport();
    final connection = MeshtasticConnectionController();
    final session = MeshtasticRadioSession(
      transport: transport,
      connection: connection,
    );

    await session.connect(deviceName: 'Trail Radio');
    expect(connection.state, MeshtasticConnectionState.connected);

    final received = <Uint8List>[];
    final subscription = session.incomingEnvelopes.listen(received.add);
    transport.controller.add(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    expect(received.single, orderedEquals([1, 2, 3]));

    await session.send(Uint8List.fromList([4, 5]));
    expect(transport.sent.single, orderedEquals([4, 5]));

    await session.disconnect();
    expect(connection.state, MeshtasticConnectionState.disconnected);

    await subscription.cancel();
    await transport.controller.close();
    await session.dispose();
  });

  test('session refuses writes while disconnected', () async {
    final session = MeshtasticRadioSession(
      transport: FakeRadioTransport(),
      connection: MeshtasticConnectionController(),
    );

    expect(
      session.send(Uint8List.fromList([1])),
      throwsA(isA<StateError>()),
    );
    await session.dispose();
  });

  test('BLE identifiers match the Meshtastic PhoneAPI service', () {
    expect(MeshtasticBleGatt.service,
        '6ba1b218-15a8-461f-9fa8-5dcae273eafd');
    expect(MeshtasticBleGatt.toRadio,
        'f75c76d2-129e-4dad-a1dd-7866124401e7');
    expect(MeshtasticBleGatt.fromRadio,
        '2c55e69e-4993-11ed-b878-0242ac120002');
    expect(MeshtasticBleGatt.fromNum,
        'ed9da18c-a800-4f66-a670-aa7547e34453');
  });
}
