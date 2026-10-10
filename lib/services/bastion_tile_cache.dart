import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps map tiles you have viewed available offline.
///
/// flutter_map caches tiles by default, but in an OS cache directory that
/// Android may clear, and it refetches tiles once the server's freshness
/// window (often days) passes, so they vanish offline. Bastion stores tiles
/// in app support storage and treats them as fresh for a year.
///
/// It does not bulk-download areas: the OpenStreetMap tile servers' usage
/// policy forbids pre-fetching.
abstract final class BastionTileCache {
  static const maxBytes = 500 * 1024 * 1024;
  static const freshFor = Duration(days: 365);

  static String? _directory;

  /// Call once before the first map is shown.
  static Future<void> initialize() async {
    try {
      _directory = '${(await getApplicationSupportDirectory()).path}/map_tiles';
      _create();
    } catch (error) {
      // Tests and unsupported platforms fall back to flutter_map's default.
      debugPrint('Offline map cache unavailable: $error');
    }
  }

  static void _create() => BuiltInMapCachingProvider.getOrCreateInstance(
        cacheDirectory: _directory,
        maxCacheSize: maxBytes,
        overrideFreshAge: freshFor,
      );

  /// Bytes currently stored, or null when unknown.
  static Future<int?> sizeBytes() async {
    final path = _directory;
    if (path == null) return null;
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Deletes all saved tiles and starts a fresh cache with the same settings.
  static Future<void> clear() async {
    if (_directory == null) return;
    await BuiltInMapCachingProvider.getOrCreateInstance().destroy(deleteCache: true);
    _create();
  }
}
