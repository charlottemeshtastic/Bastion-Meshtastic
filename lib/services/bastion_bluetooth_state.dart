import 'dart:async';

import 'package:universal_ble/universal_ble.dart';

/// Whether the phone's Bluetooth adapter is on, behind an interface so the
/// reconnect logic can be tested without a real adapter.
abstract interface class BluetoothAvailability {
  Future<bool> isOn();

  /// Emits true when Bluetooth turns on and false when it turns off.
  Stream<bool> get changes;
}

class UniversalBleAvailability implements BluetoothAvailability {
  @override
  Future<bool> isOn() async {
    try {
      return await UniversalBle.getBluetoothAvailabilityState() == AvailabilityState.poweredOn;
    } catch (_) {
      // Unknown state must not block reconnecting.
      return true;
    }
  }

  @override
  Stream<bool> get changes {
    try {
      return UniversalBle.availabilityStream
          .where((s) => s == AvailabilityState.poweredOn || s == AvailabilityState.poweredOff)
          .map((s) => s == AvailabilityState.poweredOn)
          .handleError((Object _) {});
    } catch (_) {
      return const Stream.empty();
    }
  }
}
