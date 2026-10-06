import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../meshtastic/radio_session.dart';
import '../meshtastic/radio_transport.dart';

abstract class ConnectionServiceBackend {
  bool get supported;
  Stream<void> get stops;
  Future<bool> requestNotifications();
  Future<bool> start(String status);
  Future<void> stop();
  Future<bool> running();
  Future<bool> heartbeat();
}

class AndroidConnectionService implements ConnectionServiceBackend {
  AndroidConnectionService() {
    if (supported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'stopped') {
          _stops.add(null);
        }
      });
    }
  }
  static const _channel = MethodChannel('bastion/connection');
  final _stops = StreamController<void>.broadcast();
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Stream<void> get stops => _stops.stream;
  @override
  Future<bool> requestNotifications() async =>
      await _channel.invokeMethod<bool>('requestNotifications') == true;
  @override
  Future<bool> start(String status) async =>
      await _channel.invokeMethod<bool>('start', {'status': status}) == true;
  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
  @override
  Future<bool> running() async =>
      await _channel.invokeMethod<bool>('running') == true;
  @override
  Future<bool> heartbeat() async =>
      await _channel.invokeMethod<bool>('heartbeat') == true;
}

/// Connection intent is runtime-only. Recover only the user-selected transport
/// and the verified radio identity; never restore sends or Bot Mode on reconnect.
class ConnectionManager extends ChangeNotifier {
  ConnectionManager(
    this.session, {
    ConnectionServiceBackend? backend,
    this.retryDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 40),
      Duration(seconds: 60),
    ],
  }) : backend = backend ?? AndroidConnectionService() {
    session.addListener(_changed);
    _stops = this.backend.stops.listen((_) {
      if ((screenOff || starting) && !_stopping) {
        unawaited(stop());
      }
    });
  }
  final RadioSession session;
  final ConnectionServiceBackend backend;
  final List<Duration> retryDelays;
  late final StreamSubscription<void> _stops;
  RadioTransport Function()? _factory;
  int? _verifiedRadio;
  Timer? _retry;
  Timer? _heartbeat;
  bool _disposed = false;
  bool _connecting = false;
  bool _stopping = false;
  bool foreground = true;
  bool screenOff = false;
  bool autoReconnect = false;
  bool starting = false;
  int attempts = 0;
  int _generation = 0;
  String? error;
  bool get supported => backend.supported;
  bool get retryPending => _retry != null;
  bool get canRecover => _factory != null && _verifiedRadio != null;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    if (!supported) {
      return;
    }
    try {
      // A restarted Dart/UI session never silently adopts an older lease.
      if (await backend.running()) {
        await backend.stop();
      }
    } catch (_) {
      error = 'Screen-off service is unavailable on this device.';
      _notify();
    }
  }

  Future<void> connect(RadioTransport Function() factory) async {
    if (_disposed || _connecting) {
      return;
    }
    await stop();
    if (_disposed) {
      return;
    }
    _factory = factory;
    _verifiedRadio = null;
    attempts = 0;
    error = null;
    _connecting = true;
    try {
      await session.connect(factory());
    } catch (_) {
      error = 'Could not open the selected radio.';
    } finally {
      _connecting = false;
      _changed();
    }
  }

  void setAutoReconnect(bool value) {
    if (_disposed || starting || _stopping) {
      return;
    }
    if (value && !canRecover) {
      error = 'Connect and verify a radio before enabling recovery.';
      _notify();
      return;
    }
    autoReconnect = value;
    error = null;
    _generation++;
    _retry?.cancel();
    _retry = null;
    attempts = 0;
    if (value) {
      _changed();
    } else if (session.status != RadioStatus.ready && screenOff) {
      unawaited(stop());
    }
    _notify();
  }

  Future<void> setScreenOff(bool value) async {
    if (_disposed || starting || _stopping) {
      return;
    }
    if (!value) {
      await stop();
      return;
    }
    if (!supported ||
        !foreground ||
        session.status != RadioStatus.ready ||
        !canRecover) {
      error =
          'Connect a verified radio and enable screen-off mode while the app is visible.';
      _notify();
      return;
    }
    starting = true;
    error = null;
    final generation = _generation;
    _notify();
    try {
      if (!await backend.requestNotifications()) {
        throw StateError('Allow notifications for the visible STOP control.');
      }
      if (_disposed ||
          generation != _generation ||
          !foreground ||
          session.status != RadioStatus.ready) {
        return;
      }
      final success = await backend.start(
        'Connection service active · radio !${_verifiedRadio!.toRadixString(16).padLeft(8, '0')}',
      );
      if (!success) {
        throw StateError('Android did not confirm the connection service.');
      }
      if (_disposed || generation != _generation || !foreground) {
        await backend.stop();
        return;
      }
      screenOff = true;
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        unawaited(_checkLease());
      });
    } catch (e) {
      screenOff = false;
      error = 'Screen-off mode could not start: $e';
    } finally {
      starting = false;
      _notify();
    }
  }

  Future<void> _checkLease() async {
    if (!screenOff || _disposed) {
      return;
    }
    try {
      if (!await backend.heartbeat()) {
        error = 'Android stopped screen-off monitoring.';
        await stop();
      }
    } catch (_) {
      error = 'Connection service lost; monitoring stopped.';
      await stop();
    }
  }

  Future<void> onForeground(bool value) async {
    foreground = value;
    if (!value && !screenOff) {
      _generation++;
      _retry?.cancel();
      _retry = null;
      await session.disconnect();
    } else if (value) {
      if (screenOff) {
        await _checkLease();
      }
      _changed();
    }
    _notify();
  }

  void _changed() {
    if (_disposed || _stopping) {
      return;
    }
    if (session.status == RadioStatus.ready) {
      final radio = session.localNode;
      if (_verifiedRadio != null && radio != _verifiedRadio) {
        error =
            'Radio identity changed. Recovery stopped; select and verify it again.';
        unawaited(stop());
        return;
      }
      _verifiedRadio = radio;
      _retry?.cancel();
      _retry = null;
      attempts = 0;
      _notify();
      return;
    }
    final busy =
        session.status == RadioStatus.connecting ||
        session.status == RadioStatus.downloading;
    if (!busy &&
        !_connecting &&
        autoReconnect &&
        canRecover &&
        (foreground || screenOff)) {
      _scheduleRetry();
    } else if (!busy && !_connecting && screenOff && !autoReconnect) {
      unawaited(stop());
    }
    _notify();
  }

  void _scheduleRetry() {
    if (_retry != null || _stopping || _disposed) {
      return;
    }
    if (attempts >= retryDelays.length) {
      error =
          'Recovery exhausted after ${retryDelays.length} attempts. Reconnect manually.';
      unawaited(stop());
      return;
    }
    final delay = retryDelays[attempts];
    final generation = _generation;
    _retry = Timer(delay, () {
      _retry = null;
      if (_disposed ||
          generation != _generation ||
          !autoReconnect ||
          !(foreground || screenOff)) {
        return;
      }
      _connecting = true;
      attempts++;
      _notify();
      unawaited(_recover(generation));
    });
  }

  Future<void> _recover(int generation) async {
    try {
      if (!_disposed && generation == _generation && _factory != null) {
        await session.connect(_factory!());
      }
    } catch (_) {
      error = 'Recovery attempt could not open the radio.';
    } finally {
      _connecting = false;
      if (generation == _generation) {
        _changed();
      }
    }
  }

  Future<void> stop() async {
    if (_stopping || _disposed) {
      return;
    }
    _stopping = true;
    _generation++;
    autoReconnect = false;
    screenOff = false;
    _retry?.cancel();
    _retry = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _notify();
    try {
      await session.disconnect();
      if (supported) {
        await backend.stop();
      }
    } catch (_) {
      error ??= 'Connection stop could not be confirmed.';
    } finally {
      _stopping = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    _heartbeat?.cancel();
    unawaited(_stops.cancel());
    session.removeListener(_changed);
    if (supported) {
      unawaited(backend.stop().catchError((Object _) {}));
    }
    super.dispose();
  }
}
