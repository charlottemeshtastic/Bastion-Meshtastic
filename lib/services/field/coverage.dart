import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/telemetry_sample.dart';
import '../meshtastic/radio_session.dart';

class FieldLocation {
  const FieldLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.time,
  });
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime time;
  bool fresh(DateTime now) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 85 &&
      longitude.abs() <= 180 &&
      accuracy.isFinite &&
      accuracy >= 0 &&
      accuracy <= 100 &&
      now.difference(time) >= const Duration(seconds: -30) &&
      now.difference(time) <= const Duration(minutes: 2);
}

abstract class FieldLocationBackend {
  bool get supported;
  Future<FieldLocation> capture();
}

class AndroidFieldLocation implements FieldLocationBackend {
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<FieldLocation> capture() async {
    final j = await const MethodChannel(
      'bastion/field',
    ).invokeMapMethod<String, dynamic>('locationFix');
    if (j == null) {
      throw StateError('No location received');
    }
    return FieldLocation(
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
      accuracy: (j['accuracy'] as num).toDouble(),
      time: DateTime.fromMillisecondsSinceEpoch(j['time'] as int),
    );
  }
}

class CoveragePoint {
  const CoveragePoint({
    required this.radio,
    required this.node,
    required this.time,
    required this.packetTime,
    required this.location,
    this.snr,
    this.rssi,
  });
  final int radio;
  final int node;
  final DateTime time;
  final DateTime packetTime;
  final FieldLocation location;
  final double? snr;
  final int? rssi;
  Map<String, Object?> toJson() => {
    'radio': radio,
    'node': node,
    'time': time.toIso8601String(),
    'packetTime': packetTime.toIso8601String(),
    'latitude': location.latitude,
    'longitude': location.longitude,
    'accuracy': location.accuracy,
    'fixTime': location.time.toIso8601String(),
    'snr': snr,
    'rssi': rssi,
  };
  factory CoveragePoint.fromJson(Map<String, dynamic> j) => CoveragePoint(
    radio: j['radio'] as int,
    node: j['node'] as int,
    time: DateTime.parse(j['time'] as String),
    packetTime: DateTime.parse(j['packetTime'] as String),
    location: FieldLocation(
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
      accuracy: (j['accuracy'] as num).toDouble(),
      time: DateTime.parse(j['fixTime'] as String),
    ),
    snr: (j['snr'] as num?)?.toDouble(),
    rssi: j['rssi'] as int?,
  );
  bool get valid =>
      radio > 0 &&
      radio < 0xffffffff &&
      node > 0 &&
      node < 0xffffffff &&
      location.fresh(time) &&
      (snr != null || rssi != null) &&
      (snr == null || snr!.isFinite);
}

class CoverageRecorder extends ChangeNotifier {
  CoverageRecorder(
    this.session, {
    FieldLocationBackend? backend,
    DateTime Function()? clock,
  }) : backend = backend ?? AndroidFieldLocation(),
       _clock = clock ?? DateTime.now {
    session.addListener(_sessionChanged);
  }
  static const storageKey = 'bastion.coverage.v1';
  final RadioSession session;
  final FieldLocationBackend backend;
  final DateTime Function() _clock;
  FieldLocation? fix;
  int? _radio;
  bool recording = false;
  bool loading = true;
  bool capturing = false;
  bool loadFailed = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _expiry;
  String? error;
  final _points = <CoveragePoint>[];
  final _last = <String, DateTime>{};
  List<CoveragePoint> get points => List.unmodifiable(_points);
  Future<void> _writes = Future.value();
  Future<void> get saved => _writes;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    try {
      final encoded = (await SharedPreferences.getInstance()).getString(
        storageKey,
      );
      if (encoded != null) {
        final restored = (jsonDecode(encoded) as List)
            .map(
              (j) =>
                  CoveragePoint.fromJson(Map<String, dynamic>.from(j as Map)),
            )
            .toList();
        if (restored.any((p) => !p.valid)) {
          throw const FormatException('Invalid measured points');
        }
        _points.addAll(restored);
        _trim();
      }
    } catch (_) {
      loadFailed = true;
      error =
          'Coverage history could not be loaded. Recording is disabled to protect it.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> start() async {
    if (_disposed || loading || loadFailed || capturing || !backend.supported) {
      return;
    }
    if (session.status != RadioStatus.ready) {
      error = 'Connect a radio before recording.';
      _notify();
      return;
    }
    _expiry?.cancel();
    final generation = ++_generation;
    final radio = session.localNode;
    _radio = radio;
    capturing = true;
    recording = false;
    error = null;
    _notify();
    try {
      final location = await backend.capture();
      if (_disposed ||
          generation != _generation ||
          session.status != RadioStatus.ready ||
          radio != session.localNode) {
        return;
      }
      if (!location.fresh(_clock())) {
        throw StateError('Location must be fresh and accurate within 100 m.');
      }
      fix = location;
      _radio = radio;
      recording = true;
      _expiry = Timer(
        const Duration(minutes: 2) - _clock().difference(location.time),
        () {
          if (!_disposed && generation == _generation && recording) {
            recording = false;
            error = 'Location fix expired. Capture a new point to continue.';
            _notify();
          }
        },
      );
    } catch (e) {
      error = 'Location capture failed: $e';
    } finally {
      capturing = false;
      _notify();
    }
  }

  void stop() {
    _generation++;
    _expiry?.cancel();
    _expiry = null;
    recording = false;
    _radio = null;
    _notify();
  }

  void _sessionChanged() {
    if (session.status != RadioStatus.ready || session.localNode != _radio) {
      if (recording || capturing) {
        stop();
      }
    }
  }

  void record(TelemetrySample sample) {
    if (_disposed ||
        !recording ||
        loading ||
        loadFailed ||
        fix == null ||
        sample.radio != _radio ||
        session.status != RadioStatus.ready ||
        sample.viaMqtt) {
      return;
    }
    final now = _clock();
    if (!fix!.fresh(now)) {
      _expiry?.cancel();
      _expiry = null;
      recording = false;
      error = 'Location fix expired. Capture a new point to continue.';
      _notify();
      return;
    }
    final age = now.difference(sample.time);
    if (age > const Duration(minutes: 2) ||
        age < const Duration(seconds: -30) ||
        (sample.snr == null && sample.rssi == null) ||
        (sample.snr != null && !sample.snr!.isFinite)) {
      return;
    }
    final key = '${sample.radio}:${sample.node}';
    final last = _last[key];
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    final point = CoveragePoint(
      radio: sample.radio,
      node: sample.node,
      time: now,
      packetTime: sample.time,
      location: fix!,
      snr: sample.snr,
      rssi: sample.rssi,
    );
    if (!point.valid) {
      return;
    }
    _last[key] = now;
    _points.add(point);
    _trim();
    _persist();
    _notify();
  }

  void _trim() {
    _points.removeWhere(
      (p) => _clock().difference(p.time) > const Duration(days: 30),
    );
    if (_points.length > 2000) {
      _points.removeRange(0, _points.length - 2000);
    }
    _last.removeWhere(
      (_, t) => _clock().difference(t) > const Duration(minutes: 2),
    );
  }

  String csv() => [
    'recorded_utc,packet_utc,radio,node,receiver_latitude,receiver_longitude,fix_utc,accuracy_m,rx_snr_db,rx_rssi_dbm',
    for (final p in points)
      [
        p.time.toUtc().toIso8601String(),
        p.packetTime.toUtc().toIso8601String(),
        p.radio,
        p.node,
        p.location.latitude,
        p.location.longitude,
        p.location.time.toUtc().toIso8601String(),
        p.location.accuracy,
        p.snr ?? '',
        p.rssi ?? '',
      ].join(','),
  ].join('\n');
  Future<void> clear() async {
    if (loading || loadFailed || capturing) {
      return;
    }
    stop();
    _points.clear();
    _last.clear();
    _persist();
    _notify();
    await saved;
  }

  void _persist() {
    final encoded = jsonEncode(_points.map((p) => p.toJson()).toList());
    _writes = _writes.then((_) async {
      try {
        if (!await (await SharedPreferences.getInstance()).setString(
          storageKey,
          encoded,
        )) {
          throw StateError('Save failed');
        }
      } catch (_) {
        recording = false;
        error = 'Coverage could not be saved. Recording stopped.';
        _notify();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    _generation++;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}
