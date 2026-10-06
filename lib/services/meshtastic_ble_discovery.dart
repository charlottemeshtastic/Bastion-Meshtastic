import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'meshtastic/ble_radio_transport.dart';

/// Scan candidates must still pass GATT discovery and protocol synchronization.
class MeshtasticBleDiscovery extends ChangeNotifier {
  StreamSubscription<List<ScanResult>>? _subscription;
  StreamSubscription<bool>? _scanState;
  final Map<String, ScanResult> _results = {};
  bool _scanning = false;
  bool _disposed = false;
  int _generation = 0;
  String? _error;
  bool get scanning => _scanning;
  String? get error => _error;
  List<ScanResult> get results => List.unmodifiable(_results.values);

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> scan() async {
    if (_scanning || _disposed) {
      return;
    }
    final generation = ++_generation;
    _results.clear();
    _error = null;
    _scanning = true;
    _notify();
    try {
      if (!await FlutterBluePlus.isSupported) {
        throw StateError('Bluetooth LE is not supported on this device.');
      }
      if (_disposed || generation != _generation) {
        return;
      }
      await _subscription?.cancel();
      await _scanState?.cancel();
      if (_disposed || generation != _generation) {
        return;
      }
      var scanStarted = false;
      _subscription = FlutterBluePlus.onScanResults.listen((batch) {
        if (_disposed || generation != _generation) {
          return;
        }
        for (final item in batch) {
          if (item.advertisementData.serviceUuids.contains(Guid(meshtasticServiceUuid))) {
            _results[item.device.remoteId.str] = item;
          }
        }
        _notify();
      }, onError: (Object error) {
        _error = error.toString();
        _notify();
      });
      _scanState = FlutterBluePlus.isScanning.listen((value) {
        if (!_disposed && generation == _generation && scanStarted && !value &&
            FlutterBluePlus.isScanningNow == false) {
          _scanning = false;
          _notify();
        }
      });
      await FlutterBluePlus.startScan(withServices: [Guid(meshtasticServiceUuid)],
        timeout: const Duration(seconds: 10));
      scanStarted = true;
      if (_disposed || generation != _generation) {
        await FlutterBluePlus.stopScan();
        return;
      }
      if (!_disposed && generation == _generation) {
        _scanning = FlutterBluePlus.isScanningNow;
        _notify();
      }
    } catch (e) {
      _error = e.toString();
      _scanning = false;
      _notify();
    }
  }

  Future<void> stop() async {
    ++_generation;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _error = e.toString();
    }
    _scanning = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    unawaited(_scanState?.cancel());
    if (_scanning) {
      unawaited(FlutterBluePlus.stopScan().catchError((Object _) {}));
    }
    super.dispose();
  }
}
