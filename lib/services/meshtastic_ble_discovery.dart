import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

class MeshtasticBleDevice {
  const MeshtasticBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.advertisedServices,
  });

  final String id;
  final String name;
  final int rssi;
  final List<String> advertisedServices;

  bool get advertisesMeshtastic => advertisedServices
      .map((value) => value.toLowerCase())
      .contains('6ba1b218-15a8-461f-9fa8-5dcae273eafd');
}

/// Discovers nearby BLE peripherals. Discovery alone never promotes a
/// peripheral to a verified Meshtastic mesh node.
class MeshtasticBleDiscovery extends ChangeNotifier {
  StreamSubscription<BleDevice>? _subscription;
  final Map<String, MeshtasticBleDevice> _results = {};
  bool _scanning = false;
  String? _error;

  bool get scanning => _scanning;
  String? get error => _error;
  List<MeshtasticBleDevice> get results {
    final values = _results.values.toList()
      ..sort((a, b) {
        if (a.advertisesMeshtastic != b.advertisesMeshtastic) {
          return a.advertisesMeshtastic ? -1 : 1;
        }
        return b.rssi.compareTo(a.rssi);
      });
    return List.unmodifiable(values);
  }

  Future<void> scan() async {
    if (_scanning) return;
    _results.clear();
    _error = null;
    _scanning = true;
    notifyListeners();

    try {
      await UniversalBle.requestPermissions();
      await _subscription?.cancel();
      _subscription = UniversalBle.scanStream.listen(
        (device) {
          _results[device.deviceId] = MeshtasticBleDevice(
            id: device.deviceId,
            name: (device.name?.trim().isNotEmpty ?? false)
                ? device.name!.trim()
                : 'Unnamed BLE device',
            rssi: device.rssi ?? -127,
            advertisedServices: List.unmodifiable(device.services),
          );
          notifyListeners();
        },
        onError: (Object error) {
          _error = error.toString();
          notifyListeners();
        },
      );

      await UniversalBle.startScan();
      await Future<void>.delayed(const Duration(seconds: 10));
    } catch (error) {
      _error = error.toString();
    } finally {
      await _stopNativeScan();
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await _stopNativeScan();
    } catch (error) {
      _error = error.toString();
    }
    _scanning = false;
    notifyListeners();
  }

  Future<void> _stopNativeScan() async {
    await UniversalBle.stopScan();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
