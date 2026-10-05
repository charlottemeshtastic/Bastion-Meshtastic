import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion_meshtastic/generated/meshtastic/channel.pb.dart';
import 'package:bastion_meshtastic/generated/meshtastic/telemetry.pb.dart';
import 'package:bastion_meshtastic/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_transport.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'package:bastion_meshtastic/models/telemetry_sample.dart';

class FakeTransport implements RadioTransport {
  final input = StreamController<List<int>>.broadcast(sync: true);
  final lost = StreamController<void>.broadcast(sync: true);
  final writes = <List<int>>[];
  bool closed = false;
  bool failOpen = false;
  Completer<void>? openGate;
  @override
  Stream<List<int>> get frames => input.stream;
  @override
  Stream<void> get disconnections => lost.stream;
  @override
  Future<void> open() async {
    await openGate?.future;
    if (failOpen) {
      throw StateError('Pairing rejected');
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    writes.add(bytes);
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  void emit(pb.FromRadio value) => input.add(value.writeToBuffer());
  Future<void> finish() async {
    await input.close();
    await lost.close();
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);
  late RadioSession session;
  late FakeTransport transport;
  setUp(() {
    session = RadioSession(
      clock: () => now,
      nonce: () => 123,
      configTimeout: const Duration(milliseconds: 50),
    );
    transport = FakeTransport();
  });
  tearDown(() async {
    await session.disconnect();
    session.dispose();
    await transport.finish();
  });
  void ready() {
    transport.emit(pb.FromRadio(myInfo: pb.MyNodeInfo(myNodeNum: 42)));
    transport.emit(pb.FromRadio(configCompleteId: 123));
  }

  test(
    'writes ToRadio and requires matching config nonce plus valid identity',
    () async {
      await session.connect(transport);
      expect(pb.ToRadio.fromBuffer(transport.writes.single).wantConfigId, 123);
      transport.emit(pb.FromRadio(channel: Channel(index: 0)));
      transport.emit(pb.FromRadio(configCompleteId: 999));
      expect(session.status, RadioStatus.downloading);
      ready();
      expect(session.status, RadioStatus.ready);
      expect(session.channels.keys, contains(0));
      expect(session.localNode, 42);
    },
  );

  test(
    'configuration snapshot is silent; live telemetry emits verified observations',
    () async {
      final observations = <int>[];
      final sub = session.observations.listen(
        (n) => observations.add(n.number),
      );
      await session.connect(transport);
      transport.emit(
        pb.FromRadio(
          nodeInfo: pb.NodeInfo(
            num: 7,
            user: pb.User(longName: 'Mountain repeater'),
            lastHeard: now.millisecondsSinceEpoch ~/ 1000 - 60,
            deviceMetrics: DeviceMetrics(batteryLevel: 80),
          ),
        ),
      );
      expect(observations, isEmpty);
      ready();
      final telemetry = Telemetry(
        deviceMetrics: DeviceMetrics(batteryLevel: 15),
      );
      transport.emit(
        pb.FromRadio(
          packet: pb.MeshPacket(
            from: 7,
            id: 10,
            rxTime: now.millisecondsSinceEpoch ~/ 1000,
            rxSnr: 4,
            decoded: pb.Data(
              portnum: PortNum.TELEMETRY_APP,
              payload: telemetry.writeToBuffer(),
            ),
          ),
        ),
      );
      expect(session.nodes.single.battery, 15);
      expect(session.nodes.single.displayName, 'Mountain repeater');
      expect(observations, [7]);
      // Replay must not fire another observation.
      transport.emit(pb.FromRadio(packet: pb.MeshPacket(from: 7, id: 10)));
      expect(observations, [7]);
      await sub.cancel();
    },
  );

  test(
    'externally powered telemetry is not displayed as a low battery',
    () async {
      await session.connect(transport);
      ready();
      transport.emit(
        pb.FromRadio(
          packet: pb.MeshPacket(
            from: 7,
            id: 20,
            decoded: pb.Data(
              portnum: PortNum.TELEMETRY_APP,
              payload: Telemetry(
                deviceMetrics: DeviceMetrics(batteryLevel: 101),
              ).writeToBuffer(),
            ),
          ),
        ),
      );
      expect(session.nodes.single.powered, isTrue);
      expect(session.nodes.single.battery, isNull);
    },
  );

  test(
    'history records fresh packet fields without repeating cached battery',
    () async {
      final samples = <TelemetrySample>[];
      final sub = session.telemetry.listen(samples.add);
      await session.connect(transport);
      ready();
      transport.emit(
        pb.FromRadio(
          packet: pb.MeshPacket(
            from: 7,
            id: 30,
            rxSnr: 4,
            decoded: pb.Data(
              portnum: PortNum.TELEMETRY_APP,
              payload: Telemetry(
                deviceMetrics: DeviceMetrics(batteryLevel: 18, voltage: 3.7),
              ).writeToBuffer(),
            ),
          ),
        ),
      );
      transport.emit(
        pb.FromRadio(packet: pb.MeshPacket(from: 7, id: 31, rxSnr: 2)),
      );
      expect(samples, hasLength(2));
      expect(samples.first.battery, 18);
      expect(samples.first.voltage, closeTo(3.7, 0.01));
      expect(samples.last.battery, isNull);
      expect(samples.last.snr, 2);
      expect(session.nodes.single.battery, 18);
      transport.emit(
        pb.FromRadio(packet: pb.MeshPacket(from: 7, id: 31, rxSnr: 2)),
      );
      expect(samples, hasLength(2));
      await sub.cancel();
    },
  );

  test(
    'invalid or partial positions do not overwrite a valid location',
    () async {
      await session.connect(transport);
      ready();
      void position(int id, pb.Position p) => transport.emit(
        pb.FromRadio(
          packet: pb.MeshPacket(
            from: 7,
            id: id,
            decoded: pb.Data(
              portnum: PortNum.POSITION_APP,
              payload: p.writeToBuffer(),
            ),
          ),
        ),
      );
      position(
        40,
        pb.Position(
          latitudeI: 353200000,
          longitudeI: -838000000,
          time: now.millisecondsSinceEpoch ~/ 1000,
        ),
      );
      expect(session.nodes.single.hasPosition, true);
      expect(session.nodes.single.positionTime, now);
      position(41, pb.Position(latitudeI: 0, longitudeI: 0));
      position(42, pb.Position(latitudeI: 500000000));
      position(43, pb.Position(latitudeI: 1000000000, longitudeI: -838000000));
      expect(session.nodes.single.latitude, closeTo(35.32, 0.0001));
      expect(session.nodes.single.longitude, closeTo(-83.8, 0.0001));
    },
  );

  test('old node info cannot overwrite newer telemetry', () async {
    await session.connect(transport);
    ready();
    transport.emit(
      pb.FromRadio(
        packet: pb.MeshPacket(
          from: 7,
          id: 21,
          decoded: pb.Data(
            portnum: PortNum.TELEMETRY_APP,
            payload: Telemetry(
              deviceMetrics: DeviceMetrics(batteryLevel: 12),
            ).writeToBuffer(),
          ),
        ),
      ),
    );
    transport.emit(
      pb.FromRadio(
        nodeInfo: pb.NodeInfo(
          num: 7,
          lastHeard: now.millisecondsSinceEpoch ~/ 1000 - 3600,
          deviceMetrics: DeviceMetrics(batteryLevel: 90),
        ),
      ),
    );
    expect(session.nodes.single.battery, 12);
  });

  test(
    'malformed protobuf is ignored; lost BLE connection stops monitoring',
    () async {
      await session.connect(transport);
      ready();
      transport.input.add([0xff]);
      expect(session.malformedFrames, 1);
      expect(session.status, RadioStatus.ready);
      transport.lost.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(session.status, RadioStatus.disconnected);
      expect(session.readySince, isNull);
      expect(transport.closed, isTrue);
    },
  );

  test('timeout leaves no connected transport', () async {
    await session.connect(transport);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(session.status, RadioStatus.error);
    expect(session.error, contains('timed out'));
    expect(transport.closed, isTrue);
  });

  test('failed pairing closes transport and reports error', () async {
    transport.failOpen = true;
    await session.connect(transport);
    await Future<void>.delayed(Duration.zero);
    expect(session.status, RadioStatus.error);
    expect(session.error, contains('Pairing rejected'));
    expect(transport.closed, isTrue);
  });

  test(
    'cancelling during connect cannot start a late protocol session',
    () async {
      transport.openGate = Completer<void>();
      final pending = session.connect(transport);
      await Future<void>.delayed(Duration.zero);
      await session.disconnect();
      transport.openGate!.complete();
      await pending;
      expect(session.status, RadioStatus.disconnected);
      expect(transport.closed, isTrue);
      expect(transport.writes, isEmpty);
    },
  );

  test(
    'a configuration completion without identity cannot become ready',
    () async {
      await session.connect(transport);
      transport.emit(pb.FromRadio(configCompleteId: 123));
      expect(session.status, RadioStatus.error);
    },
  );
}
