import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/models/mesh_node.dart';
import 'package:bastion_meshtastic/models/telemetry_sample.dart';
import 'package:bastion_meshtastic/services/node_archive.dart';
import 'package:bastion_meshtastic/services/geo.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'restores nodes, positions and readings separately for each radio',
    () async {
      final archive = NodeArchive(clock: () => now);
      await archive.load();
      archive.seed(42, [
        MeshNode(
          number: 7,
          name: 'Ridge',
          lastHeard: now,
          latitude: 35.32,
          longitude: -83.8,
          positionTime: now,
        ),
      ]);
      archive.seed(43, [
        MeshNode(number: 7, name: 'Different mesh', lastHeard: now),
      ]);
      archive.record(
        TelemetrySample(radio: 42, node: 7, time: now, battery: 18, snr: 4),
      );
      await archive.saved;
      final restored = NodeArchive(clock: () => now);
      await restored.load();
      expect(restored.nodesFor(42).single.displayName, 'Ridge');
      expect(restored.nodesFor(42).single.positionTime, now);
      expect(restored.nodesFor(43).single.displayName, 'Different mesh');
      expect(restored.samplesFor(42, 7).single.battery, 18);
      expect(restored.samplesFor(43, 7), isEmpty);
      await restored.clearRadio(42);
      expect(restored.nodesFor(42), isEmpty);
      expect(restored.samplesFor(42, 7), isEmpty);
      expect(restored.nodesFor(43), hasLength(1));
      archive.dispose();
      restored.dispose();
    },
  );

  test(
    'retains known position on partial update and rejects older updates',
    () async {
      final archive = NodeArchive(clock: () => now);
      await archive.load();
      archive.observe(
        42,
        MeshNode(
          number: 7,
          lastHeard: now,
          latitude: 35,
          longitude: -83,
          positionTime: now,
          battery: 18,
        ),
      );
      archive.observe(
        42,
        MeshNode(
          number: 7,
          lastHeard: now.add(const Duration(seconds: 10)),
          name: 'Ridge',
        ),
      );
      expect(archive.nodesFor(42).single.hasPosition, true);
      expect(archive.nodesFor(42).single.battery, 18);
      archive.observe(
        42,
        MeshNode(
          number: 7,
          lastHeard: now.subtract(const Duration(days: 1)),
          battery: 99,
        ),
      );
      expect(archive.nodesFor(42).single.battery, 18);
      await archive.saved;
      archive.dispose();
    },
  );

  test('bounds readings and discards old history', () async {
    final archive = NodeArchive(clock: () => now);
    // Events during load are retained in memory and saved once loading completes.
    archive.record(
      TelemetrySample(
        radio: 42,
        node: 7,
        time: now.subtract(const Duration(days: 31)),
        battery: 1,
      ),
    );
    for (var i = 0; i < NodeArchive.maxSamples + 5; i++) {
      archive.record(
        TelemetrySample(
          radio: 42,
          node: 7,
          time: now.subtract(Duration(seconds: i)),
          snr: i.toDouble(),
        ),
      );
    }
    await archive.load();
    await archive.saved;
    expect(archive.samplesFor(42, 7), hasLength(NodeArchive.maxSamples));
    expect(archive.samplesFor(42, 7).any((s) => s.battery == 1), false);
    archive.dispose();
  });

  test('corrupt storage is preserved rather than overwritten', () async {
    SharedPreferences.setMockInitialValues({NodeArchive.storageKey: '{broken'});
    final archive = NodeArchive(clock: () => now);
    await archive.load();
    expect(archive.error, isNotNull);
    archive.seed(42, [const MeshNode(number: 7)]);
    await archive.saved;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(NodeArchive.storageKey), '{broken');
    archive.dispose();
  });

  test(
    'geometry handles missing positions and the international date line',
    () {
      expect(MeshNode.validPosition(0, 0), false);
      expect(MeshNode.validPosition(91, -83), false);
      expect(MeshNode.validPosition(double.nan, -83), false);
      expect(
        nodeDistance(const MeshNode(number: 1), const MeshNode(number: 2)),
        isNull,
      );
      const a = MeshNode(number: 1, latitude: 1, longitude: 179.9);
      const b = MeshNode(number: 2, latitude: 1, longitude: -179.9);
      final result = nodeDistance(a, b)!;
      expect(result.km, closeTo(22.235, 0.1));
      expect(result.bearing, closeTo(90, 0.1));
      expect(nodeDistance(a, a)!.km, 0);
    },
  );
}
