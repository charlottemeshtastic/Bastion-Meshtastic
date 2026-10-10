import 'dart:async';

import 'package:bastion/services/bastion_background_service.dart';
import 'package:bastion/services/bastion_bluetooth_state.dart';
import 'package:bastion/services/meshtastic_ble_discovery.dart';
import 'package:bastion/services/meshtastic_connection_controller.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBluetooth implements BluetoothAvailability {
  bool on = false;
  final controller = StreamController<bool>.broadcast();

  void turn(bool value) {
    on = value;
    controller.add(value);
  }

  @override
  Future<bool> isOn() async => on;

  @override
  Stream<bool> get changes => controller.stream;
}

class _NoKeeper implements BastionBackgroundKeeper {
  @override
  Future<void> keepAlive({required String radioName, required bool reconnecting}) async {}
  @override
  Future<void> release() async {}
}

const radioDevice = MeshtasticBleDevice(id: 'AA:BB', name: 'Trail Radio', rssi: -60, advertisedServices: []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBluetooth bluetooth;
  late MeshtasticRadioCoordinator radio;

  setUp(() {
    bluetooth = _FakeBluetooth();
    radio = MeshtasticRadioCoordinator(background: _NoKeeper(), bluetooth: bluetooth);
  });

  tearDown(() async {
    await radio.disconnect();
    radio.dispose();
  });

  test('a lost link with Bluetooth off waits instead of giving up', () async {
    await radio.recoverLinkForTest(radioDevice);
    expect(radio.isReconnecting, isTrue);
    expect(radio.connection.state, MeshtasticConnectionState.error);
    expect(radio.connection.error, contains('Bluetooth is off'));
  });

  test('turning Bluetooth back on resumes reconnecting', () async {
    await radio.recoverLinkForTest(radioDevice);
    bluetooth.turn(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(radio.isReconnecting, isTrue);
    expect(radio.connection.state, MeshtasticConnectionState.connecting);
    expect(radio.connection.deviceName, 'Trail Radio');
  });

  test('disconnect cancels waiting for Bluetooth', () async {
    await radio.recoverLinkForTest(radioDevice);
    await radio.disconnect();
    expect(radio.isReconnecting, isFalse);
    bluetooth.turn(true);
    await Future<void>.delayed(Duration.zero);
    expect(radio.isReconnecting, isFalse);
    expect(radio.connection.state, MeshtasticConnectionState.disconnected);
  });
}
