import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Discovers nearby BLE peripherals. A scan result is NOT a verified
/// Meshtastic radio or a node on the Meshtastic mesh.
class MeshtasticBleDiscovery extends ChangeNotifier {
  StreamSubscription<List<ScanResult>>? _subscription;
  final Map<String, ScanResult> _results = {};
  bool _scanning = false;
  String? _error;
  bool get scanning => _scanning;
  String? get error => _error;
  List<ScanResult> get results => List.unmodifiable(_results.values);

  Future<void> scan() async {
    if (_scanning) return;
    _results.clear();
    _error = null;
    _scanning = true;
    notifyListeners();
    try {
      if (!await FlutterBluePlus.isSupported) {
        throw StateError('Bluetooth LE is not supported on this device.');
      }
      await _subscription?.cancel();
      _subscription = FlutterBluePlus.scanResults.listen((batch) {
        for (final item in batch) {
          _results[item.device.remoteId.str] = item;
        }
        notifyListeners();
      }, onError: (Object error) {
        _error = error.toString();
        notifyListeners();
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 10));
    } catch (e) {
      _error = e.toString();
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _error = e.toString();
    }
    _scanning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
