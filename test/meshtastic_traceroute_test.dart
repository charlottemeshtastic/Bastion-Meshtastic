import 'dart:async';
import 'dart:typed_data';

import 'package:bastion/generated/meshtastic/mesh.pb.dart';
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/services/meshtastic_traceroute.dart';
import 'package:flutter_test/flutter_test.dart';

const local = 0x1;
const target = 0x9;

void main() {
  late StreamController<Uint8List> incoming;
  late List<MeshPacket> sent;
  late MeshtasticTraceroute traceroute;

  setUp(() {
    incoming = StreamController<Uint8List>.broadcast();
    sent = [];
    traceroute = MeshtasticTraceroute(
      incoming: incoming.stream,
      send: (bytes) async => sent.add(ToRadio.fromBuffer(bytes).packet),
      localNodeNum: local,
    );
  });

  tearDown(() async {
    await traceroute.dispose();
    await incoming.close();
  });

  void reply(PortNum port, List<int> payload, {int from = target}) =>
      incoming.add(FromRadio(
        packet: MeshPacket(
          from: from,
          to: local,
          decoded: Data(portnum: port, payload: payload, requestId: sent.single.id),
        ),
      ).writeToBuffer());

  test('sends a TRACEROUTE_APP request that wants a response', () async {
    unawaited(traceroute.trace(target).catchError((_) => const TracerouteResult(towards: [], back: [])));
    await Future<void>.delayed(Duration.zero);
    final packet = sent.single;
    expect(packet.to, target);
    expect(packet.decoded.portnum, PortNum.TRACEROUTE_APP);
    expect(packet.decoded.wantResponse, isTrue);
  });

  test('direct neighbour has no relays', () async {
    final result = traceroute.trace(target);
    await Future<void>.delayed(Duration.zero);
    reply(PortNum.TRACEROUTE_APP,
        RouteDiscovery(snrTowards: [24], snrBack: [-8]).writeToBuffer());
    final route = await result;
    expect(route.towards.map((h) => h.nodeNum), [target]);
    expect(route.towards.single.snrDb, 6.0);
    expect(route.back.map((h) => h.nodeNum), [local]);
    expect(route.back.single.snrDb, -2.0);
    expect(route.intermediateHops, 0);
  });

  test('multi-hop route keeps relay order and unknown SNR', () async {
    final result = traceroute.trace(target);
    await Future<void>.delayed(Duration.zero);
    reply(PortNum.TRACEROUTE_APP, RouteDiscovery(
      route: [0x5, 0x7],
      snrTowards: [40, -128, 12],
      routeBack: [0x7],
      snrBack: [4, 8],
    ).writeToBuffer());
    final route = await result;
    expect(route.towards.map((h) => h.nodeNum), [0x5, 0x7, target]);
    expect(route.towards.map((h) => h.snrDb), [10.0, null, 3.0]);
    expect(route.back.map((h) => h.nodeNum), [0x7, local]);
    expect(route.intermediateHops, 2);
  });

  test('routing error fails the trace', () async {
    final result = traceroute.trace(target);
    await Future<void>.delayed(Duration.zero);
    reply(PortNum.ROUTING_APP,
        Routing(errorReason: Routing_Error.NO_RESPONSE).writeToBuffer(), from: local);
    await expectLater(result, throwsA(isA<MeshtasticTracerouteException>()
        .having((e) => e.message, 'message', contains('NO_RESPONSE'))));
  });

  test('times out without a reply', () async {
    await expectLater(
      traceroute.trace(target, timeout: const Duration(milliseconds: 20)),
      throwsA(isA<MeshtasticTracerouteException>()),
    );
  });

  test('refuses to trace the local node', () {
    expect(() => traceroute.trace(local), throwsArgumentError);
  });
}
