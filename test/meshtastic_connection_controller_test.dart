import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/meshtastic_connection_controller.dart';

void main() {
  test('connection controller tracks a complete session lifecycle', () {
    final controller = MeshtasticConnectionController();

    expect(controller.state, MeshtasticConnectionState.disconnected);
    expect(controller.error, isNull);
    controller.beginDiscovery();
    expect(controller.state, MeshtasticConnectionState.discovering);

    controller.beginConnect('Field Radio');
    expect(controller.deviceName, 'Field Radio');
    expect(controller.state, MeshtasticConnectionState.connecting);

    controller.markConnected();
    controller.beginSync();
    controller.markReady();
    expect(controller.isReady, isTrue);

    controller.disconnect();
    expect(controller.state, MeshtasticConnectionState.disconnected);
    expect(controller.deviceName, isNull);
  });

  test('connection controller exposes transport errors', () {
    final controller = MeshtasticConnectionController();
    controller.fail(StateError('BLE session lost'));
    expect(controller.state, MeshtasticConnectionState.error);
    expect(controller.error, contains('BLE session lost'));
  });
}
