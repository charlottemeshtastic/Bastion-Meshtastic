import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/models/telemetry_sample.dart';
import 'package:bastion_meshtastic/services/field/coverage.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'connection_manager_test.dart' show AutoTransport;

class FakeLocation implements FieldLocationBackend {
  late FieldLocation fix;
  Completer<FieldLocation>? gate;
  @override
  bool get supported => true;
  @override
  Future<FieldLocation> capture() async =>
      gate == null ? fix : await gate!.future;
}

void main() {
  late DateTime now;
  late RadioSession session;
  late AutoTransport transport;
  late FakeLocation location;
  late CoverageRecorder recorder;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 5, 12);
    session = RadioSession(nonce: () => 123, clock: () => now);
    transport = AutoTransport();
    location = FakeLocation()
      ..fix = FieldLocation(
        latitude: 35.32,
        longitude: -83.8,
        accuracy: 12,
        time: now,
      );
    recorder = CoverageRecorder(session, backend: location, clock: () => now);
    await recorder.load();
    await session.connect(transport);
  });
  tearDown(() async {
    await recorder.saved;
    recorder.dispose();
    await session.disconnect();
    session.dispose();
    await transport.finish();
  });
  TelemetrySample sample({
    int node = 7,
    int radio = 42,
    double? snr = 3,
    int? rssi,
    bool mqtt = false,
  }) => TelemetrySample(
    radio: radio,
    node: node,
    time: now,
    snr: snr,
    rssi: rssi,
    viaMqtt: mqtt,
  );
  test(
    'records fresh receiver measurements, excludes MQTT and missing/cached metrics',
    () async {
      recorder.record(sample());
      expect(recorder.points, isEmpty);
      await recorder.start();
      recorder.record(sample());
      recorder.record(sample(node: 8, mqtt: true));
      recorder.record(sample(node: 9, snr: null));
      recorder.record(sample(node: 10, snr: double.nan));
      recorder.record(sample(radio: 99));
      expect(recorder.points, hasLength(1));
      expect(recorder.points.single.location.latitude, 35.32);
      expect(recorder.points.single.rssi, isNull);
      expect(recorder.csv(), contains('receiver_latitude'));
      expect(recorder.csv(), contains(',3.0,'));
    },
  );
  test(
    'limits per-node sampling and expires phone fix at two minutes',
    () async {
      await recorder.start();
      recorder.record(sample());
      recorder.record(sample());
      expect(recorder.points, hasLength(1));
      now = now.add(const Duration(seconds: 31));
      recorder.record(sample());
      expect(recorder.points, hasLength(2));
      now = now.add(const Duration(minutes: 2));
      recorder.record(sample(node: 8));
      expect(recorder.recording, isFalse);
      expect(recorder.points, hasLength(2));
    },
  );
  test('persisted measurements restore without restarting recording', () async {
    await recorder.start();
    recorder.record(sample(rssi: -105));
    await recorder.saved;
    final restored = CoverageRecorder(
      session,
      backend: location,
      clock: () => now,
    );
    await restored.load();
    expect(restored.recording, isFalse);
    expect(restored.points.single.rssi, -105);
    expect(restored.points.single.location.accuracy, 12);
    restored.dispose();
  });
  test('disconnect while capturing cannot start recording afterward', () async {
    location.gate = Completer();
    final capturing = recorder.start();
    await session.disconnect();
    location.gate!.complete(location.fix);
    await capturing;
    expect(recorder.recording, isFalse);
    expect(recorder.points, isEmpty);
  });
  test(
    'invalid location and corrupt saved measurements cannot overwrite history',
    () async {
      location.fix = FieldLocation(
        latitude: double.nan,
        longitude: -83.8,
        accuracy: 12,
        time: now,
      );
      await recorder.start();
      expect(recorder.recording, isFalse);
      recorder.dispose();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(CoverageRecorder.storageKey, '{broken');
      recorder = CoverageRecorder(session, backend: location, clock: () => now);
      await recorder.load();
      await recorder.start();
      await recorder.clear();
      expect(recorder.loadFailed, isTrue);
      expect(prefs.getString(CoverageRecorder.storageKey), '{broken');
    },
  );
}
