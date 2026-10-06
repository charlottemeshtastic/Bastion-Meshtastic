import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OfflineMapPack {
  const OfflineMapPack({
    required this.path,
    required this.name,
    required this.attribution,
    required this.minZoom,
    required this.maxZoom,
    required this.tiles,
    required this.latitude,
    required this.longitude,
  });
  final String path;
  final String name;
  final String attribution;
  final int minZoom;
  final int maxZoom;
  final int tiles;
  final double latitude;
  final double longitude;
  factory OfflineMapPack.fromJson(Map<String, dynamic> j) {
    final pack = OfflineMapPack(
      path: j['path'] as String,
      name: j['name'] as String,
      attribution: j['attribution'] as String,
      minZoom: j['minZoom'] as int,
      maxZoom: j['maxZoom'] as int,
      tiles: j['tiles'] as int,
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
    );
    if (pack.path.isEmpty ||
        pack.name.isEmpty ||
        pack.attribution.isEmpty ||
        pack.minZoom < 0 ||
        pack.maxZoom > 19 ||
        pack.maxZoom < pack.minZoom ||
        pack.tiles < 1 ||
        pack.tiles > 10000 ||
        !pack.latitude.isFinite ||
        !pack.longitude.isFinite ||
        pack.latitude.abs() > 85 ||
        pack.longitude.abs() > 180) {
      throw const FormatException('Invalid offline map metadata');
    }
    return pack;
  }
}

abstract class OfflineMapBackend {
  bool get supported;
  Future<OfflineMapPack?> load();
  Future<OfflineMapPack?> importPack();
  Future<void> clear();
}

class AndroidOfflineMaps implements OfflineMapBackend {
  static const channel = MethodChannel('bastion/field');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<OfflineMapPack?> _call(String method) async {
    final value = await channel.invokeMapMethod<String, dynamic>(method);
    return value == null ? null : OfflineMapPack.fromJson(value);
  }

  @override
  Future<OfflineMapPack?> load() => _call('mapPack');
  @override
  Future<OfflineMapPack?> importPack() => _call('importMapPack');
  @override
  Future<void> clear() => channel.invokeMethod<void>('clearMapPack');
}

class OfflineMaps extends ChangeNotifier {
  OfflineMaps({OfflineMapBackend? backend})
    : backend = backend ?? AndroidOfflineMaps();
  final OfflineMapBackend backend;
  OfflineMapPack? pack;
  bool busy = false;
  bool failedLoad = false;
  String? error;
  bool _disposed = false;
  int revision = 0;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (!backend.supported || busy) {
      return;
    }
    busy = true;
    try {
      pack = await backend.load();
      failedLoad = false;
    } catch (_) {
      failedLoad = true;
      error =
          'Offline map could not be read. Import is disabled to protect it.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importPack() async {
    if (!backend.supported || busy || failedLoad) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final imported = await backend.importPack();
      if (imported != null) {
        pack = imported;
        revision++;
      }
    } catch (e) {
      error = 'Map import failed; the previous pack is kept. $e';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> clear() async {
    if (busy || failedLoad) {
      return;
    }
    busy = true;
    _notify();
    try {
      await backend.clear();
      pack = null;
      revision++;
      error = null;
    } catch (_) {
      error = 'Offline map could not be removed.';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
