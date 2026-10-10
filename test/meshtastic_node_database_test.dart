import 'dart:async';
import 'dart:typed_data';

import 'package:bastion/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/services/meshtastic_connection_controller.dart';
import 'package:bastion/services/meshtastic_node_database.dart';
import 'package:bastion/services/meshtastic_radio_session.dart';
import 'package:bastion/services/meshtastic_radio_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _IdleTransport implements MeshtasticRadioTransport {
  @override
  Stream<Uint8List> get fromRadio => const Stream.empty();
  @override
  bool get isConnected => false;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> sendToRadio(Uint8List envelope) async {}
}

Uint8List packet(int from, PortNum port, List<int> payload, {double snr = 0}) =>
    pb.FromRadio(
      packet: pb.MeshPacket(
        from: from,
        rxSnr: snr,
        decoded: pb.Data(portnum: port, payload: payload),
      ),
    ).writeToBuffer();

void main() {
  test('decodes NodeInfo identity fields used by Bastion node list', () {
    final user = <int>[
      0x0a, 0x09, ...'!1234abcd'.codeUnits,
      0x12, 0x0b, ...'Ridge Relay'.codeUnits,
      0x1a, 0x02, ...'RR'.codeUnits,
      0x28, 0x09,
    ];
    final nodeInfo = Uint8List.fromList([
      0x08, 0xac, 0xd7, 0xad, 0x0b,
      0x12, user.length, ...user,
    ]);

    final node = MeshtasticNodeInfoCodec.decode(nodeInfo);
    expect(node.num, 23817132);
    expect(node.id, '!1234abcd');
    expect(node.longName, 'Ridge Relay');
    expect(node.shortName, 'RR');
    expect(node.hardwareModel, 9);
    expect(node.displayName, 'Ridge Relay');
  });

  test('requires a node number', () {
    expect(
      () => MeshtasticNodeInfoCodec.decode(Uint8List.fromList([0x12, 0x00])),
      throwsA(isA<FormatException>()),
    );
  });

  group('live updates', () {
    final heardAt = DateTime.utc(2026, 10, 9, 12);
    late MeshtasticNodeDatabase db;
    late List<MeshtasticNode> identityUpdates;
    late StreamSubscription<MeshtasticNode> sub;

    setUp(() {
      db = MeshtasticNodeDatabase(
        MeshtasticRadioSession(
          transport: _IdleTransport(),
          connection: MeshtasticConnectionController(),
        ),
        clock: () => heardAt,
      );
      identityUpdates = [];
      sub = db.nodeUpdates.listen(identityUpdates.add);
    });

    tearDown(() async {
      await sub.cancel();
      await db.dispose();
    });

    test('NodeInfo carries position, battery and hops', () async {
      db.handleEnvelope(pb.FromRadio(nodeInfo: pb.NodeInfo(
        num: 42,
        user: pb.User(longName: 'Ridge', shortName: 'RDG'),
        position: pb.Position(latitudeI: 354512345, longitudeI: -838765432, altitude: 1200),
        hopsAway: 2,
      )).writeToBuffer());
      await Future<void>.delayed(Duration.zero);
      final node = db.nodes.single;
      expect(node.latitude, closeTo(35.4512345, 1e-7));
      expect(node.longitude, closeTo(-83.8765432, 1e-7));
      expect(node.altitudeMeters, 1200);
      expect(node.hopsAway, 2);
      expect(identityUpdates, hasLength(1));
    });

    test('position packets move a node without an identity update', () async {
      db.handleEnvelope(packet(7, PortNum.POSITION_APP,
          pb.Position(latitudeI: 100000000, longitudeI: 200000000, time: 1760000000).writeToBuffer(),
          snr: 6.5));
      await Future<void>.delayed(Duration.zero);
      final node = db.nodes.single;
      expect(node.num, 7);
      expect(node.latitude, 10.0);
      expect(node.longitude, 20.0);
      expect(node.positionTime, DateTime.fromMillisecondsSinceEpoch(1760000000000, isUtc: true));
      expect(node.lastHeard, heardAt);
      expect(node.snr, 6.5);
      expect(identityUpdates, isEmpty);
    });

    test('ignores the 0,0 no-fix position but keeps the last good one', () async {
      db.handleEnvelope(packet(7, PortNum.POSITION_APP,
          pb.Position(latitudeI: 100000000, longitudeI: 200000000).writeToBuffer()));
      db.handleEnvelope(packet(7, PortNum.POSITION_APP,
          pb.Position(latitudeI: 0, longitudeI: 0).writeToBuffer()));
      await Future<void>.delayed(Duration.zero);
      expect(db.nodes.single.latitude, 10.0);
    });

    test('node-info packets rename a node and count as identity updates', () async {
      db.handleEnvelope(packet(9, PortNum.NODEINFO_APP,
          pb.User(longName: 'Base Camp', shortName: 'BC').writeToBuffer()));
      await Future<void>.delayed(Duration.zero);
      expect(db.nodes.single.displayName, 'Base Camp');
      expect(identityUpdates.single.shortName, 'BC');
    });

    test('malformed envelopes are ignored', () {
      db.handleEnvelope(Uint8List.fromList([0xff, 0xff]));
      expect(db.nodes, isEmpty);
    });
  });
}
