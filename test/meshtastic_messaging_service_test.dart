import 'dart:async';
import 'dart:typed_data';

import 'package:bastion_meshtastic/services/meshtastic_connection_controller.dart';
import 'package:bastion_meshtastic/services/meshtastic_messaging_service.dart';
import 'package:bastion_meshtastic/services/meshtastic_radio_session.dart';
import 'package:bastion_meshtastic/services/meshtastic_radio_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements MeshtasticRadioTransport {
  final sent = <Uint8List>[];
  final controller = StreamController<Uint8List>.broadcast();
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
  test('queued COMMS message flushes automatically when radio becomes ready',
      () async {
    final transport = _FakeTransport();
    final connection = MeshtasticConnectionController();
    final session = MeshtasticRadioSession(
      transport: transport,
      connection: connection,
    );
    final messaging = MeshtasticMessagingService(
      session: session,
      connection: connection,
      packetIdFactory: () => 42,
    );

    await session.connect(deviceName: 'Field Radio');
    await messaging.start();

    await messaging.sendText(text: 'Copy');
    expect(messaging.pending, hasLength(1));
    expect(messaging.messages.single.deliveryState,
        BastionDeliveryState.queued);
    expect(transport.sent, isEmpty);

    connection.markReady();
    await Future<void>.delayed(Duration.zero);

    expect(messaging.pending, isEmpty);
    expect(transport.sent, hasLength(1));
    expect(messaging.messages.single.deliveryState,
        BastionDeliveryState.sent);

    await messaging.dispose();
    await session.dispose();
    await transport.controller.close();
  });
}
