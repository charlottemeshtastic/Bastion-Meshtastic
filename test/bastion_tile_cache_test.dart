import 'package:bastion/services/bastion_tile_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('falls back quietly where app storage is unavailable', () async {
    await BastionTileCache.initialize();
    expect(await BastionTileCache.sizeBytes(), isNull);
    await BastionTileCache.clear();
  });
}
