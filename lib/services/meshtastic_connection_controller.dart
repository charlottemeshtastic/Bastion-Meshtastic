import 'package:flutter/foundation.dart';

enum MeshtasticConnectionState {
  disconnected,
  discovering,
  connecting,
  connected,
  synchronizing,
  ready,
  error,
}

/// App-level connection state for the Meshtastic transport.
///
/// BLE discovery remains separate from a verified Meshtastic protocol session.
/// The next transport layer can drive this controller as ToRadio/FromRadio
/// support is added.
class MeshtasticConnectionController extends ChangeNotifier {
  MeshtasticConnectionState _state = MeshtasticConnectionState.disconnected;
  String? _deviceName;
  String? _error;

  MeshtasticConnectionState get state => _state;
  String? get deviceName => _deviceName;
  String? get error => _error;
  bool get isReady => _state == MeshtasticConnectionState.ready;

  void beginDiscovery() => _setState(MeshtasticConnectionState.discovering);

  void beginConnect(String deviceName) {
    _deviceName = deviceName;
    _error = null;
    _setState(MeshtasticConnectionState.connecting);
  }

  void markConnected() => _setState(MeshtasticConnectionState.connected);
  void beginSync() => _setState(MeshtasticConnectionState.synchronizing);
  void markReady() => _setState(MeshtasticConnectionState.ready);

  void fail(Object error) {
    _error = error.toString();
    _setState(MeshtasticConnectionState.error);
  }

  void disconnect() {
    _deviceName = null;
    _error = null;
    _setState(MeshtasticConnectionState.disconnected);
  }

  void _setState(MeshtasticConnectionState value) {
    if (_state == value) return;
    _state = value;
    notifyListeners();
  }
}
