import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/services/field/offline_maps.dart';

class FakeMaps implements OfflineMapBackend {
  OfflineMapPack? pack;
  OfflineMapPack? imported;
  bool fail = false;
  @override
  bool get supported => true;
  @override
  Future<OfflineMapPack?> load() async => pack;
  @override
  Future<OfflineMapPack?> importPack() async {
    if (fail) {
      throw StateError('bad ZIP');
    }
    return imported;
  }

  @override
  Future<void> clear() async {
    pack = null;
  }
}

void main() {
  const old = OfflineMapPack(
    path: '/private/current',
    name: 'Old pack',
    attribution: 'Provider license',
    minZoom: 8,
    maxZoom: 15,
    tiles: 30,
    latitude: 35.32,
    longitude: -83.8,
  );
  test(
    'cancelled and failed imports preserve existing pack; clear removes selection',
    () async {
      final backend = FakeMaps()..pack = old;
      final maps = OfflineMaps(backend: backend);
      await maps.load();
      await maps.importPack();
      expect(maps.pack, old);
      backend.fail = true;
      await maps.importPack();
      expect(maps.pack, old);
      expect(maps.error, contains('previous pack'));
      backend.fail = false;
      backend.imported = const OfflineMapPack(
        path: '/private/new',
        name: 'New',
        attribution: 'License',
        minZoom: 2,
        maxZoom: 3,
        tiles: 2,
        latitude: 35.32,
        longitude: -83.8,
      );
      await maps.importPack();
      expect(maps.pack?.name, 'New');
      expect(maps.revision, 1);
      await maps.clear();
      expect(maps.pack, isNull);
      maps.dispose();
    },
  );
  test('invalid metadata is rejected before rendering', () {
    final j = {
      'path': '/private/map',
      'name': 'Field map',
      'attribution': 'Licensed provider',
      'minZoom': 8,
      'maxZoom': 15,
      'tiles': 30,
      'latitude': 35.32,
      'longitude': -83.8,
    };
    expect(OfflineMapPack.fromJson(j).name, 'Field map');
    expect(
      () => OfflineMapPack.fromJson({...j, 'latitude': double.nan}),
      throwsFormatException,
    );
    expect(
      () => OfflineMapPack.fromJson({...j, 'maxZoom': 25}),
      throwsFormatException,
    );
    expect(
      () => OfflineMapPack.fromJson({...j, 'tiles': 10001}),
      throwsFormatException,
    );
    expect(
      () => OfflineMapPack.fromJson({...j, 'attribution': ''}),
      throwsFormatException,
    );
  });
}
