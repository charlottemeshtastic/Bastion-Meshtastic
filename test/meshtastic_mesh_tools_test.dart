import 'dart:convert';
import 'dart:typed_data';

import 'package:bastion/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/generated/meshtastic/storeforward.pb.dart';
import 'package:bastion/services/meshtastic_mesh_tools.dart';
import 'package:bastion/services/meshtastic_messaging_service.dart';
import 'package:bastion/services/meshtastic_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 10, 15);

pb.MeshPacket packet(int from, PortNum port, List<int> payload, {int to = 0x1, int id = 77, double snr = 0, int rssi = 0}) =>
    pb.MeshPacket(from: from, to: to, id: id, rxSnr: snr, rxRssi: rssi,
        decoded: pb.Data(portnum: port, payload: payload));

Uint8List envelope(pb.MeshPacket p) => pb.FromRadio(packet: p).writeToBuffer();

void main() {
  group('store & forward replay', () {
    test('direct replay keeps sender, recipient and original id', () {
      final p = packet(0x55, PortNum.STORE_FORWARD_APP, StoreAndForward(
        rr: StoreAndForward_RequestResponse.ROUTER_TEXT_DIRECT,
        text: utf8.encode('meet at the gate'),
        originalId: 4242,
      ).writeToBuffer(), to: 0x1);
      final message = MeshtasticMessagingService.storeForwardReplay(p.writeToBuffer())!;
      expect(message.from, 0x55);
      expect(message.to, 0x1);
      expect(message.packetId, 4242, reason: 'dedupes against the original');
      expect(message.text, 'meet at the gate');
    });

    test('broadcast replay becomes a channel message', () {
      final p = packet(0x55, PortNum.STORE_FORWARD_APP, StoreAndForward(
        rr: StoreAndForward_RequestResponse.ROUTER_TEXT_BROADCAST,
        text: utf8.encode('all clear'),
      ).writeToBuffer())..channel = 2;
      final message = MeshtasticMessagingService.storeForwardReplay(p.writeToBuffer())!;
      expect(message.to, MeshtasticTextCodec.broadcastNode);
      expect(message.channel, 2);
      expect(message.packetId, 77, reason: 'falls back to the packet id');
    });

    test('heartbeats and plain text are not replays', () {
      final heartbeat = packet(0x55, PortNum.STORE_FORWARD_APP,
          StoreAndForward(rr: StoreAndForward_RequestResponse.ROUTER_HEARTBEAT).writeToBuffer());
      final text = packet(0x55, PortNum.TEXT_MESSAGE_APP, utf8.encode('hi'));
      expect(MeshtasticMessagingService.storeForwardReplay(heartbeat.writeToBuffer()), isNull);
      expect(MeshtasticMessagingService.storeForwardReplay(text.writeToBuffer()), isNull);
    });
  });

  group('mesh tools', () {
    late MeshtasticMeshTools tools;
    setUp(() => tools = MeshtasticMeshTools(clock: () => now));
    tearDown(() => tools.dispose());

    test('logs range test packets with signal', () {
      expect(tools.handleEnvelope(envelope(packet(0x9, PortNum.RANGE_TEST_APP, utf8.encode('seq 12'), snr: 4.5, rssi: -98))), isTrue);
      final entry = tools.rangeTest.single;
      expect(entry.from, 0x9);
      expect(entry.text, 'seq 12');
      expect(entry.snr, 4.5);
      expect(entry.rssi, -98);
      tools.clearRangeTest();
      expect(tools.rangeTest, isEmpty);
    });

    test('learns routers from heartbeats and reports history replies', () {
      tools.handleEnvelope(envelope(packet(0x55, PortNum.STORE_FORWARD_APP, StoreAndForward(
        rr: StoreAndForward_RequestResponse.ROUTER_HEARTBEAT,
        heartbeat: StoreAndForward_Heartbeat(period: 900),
      ).writeToBuffer())));
      expect(tools.routers.single.nodeNum, 0x55);
      expect(tools.routers.single.heartbeatSecs, 900);

      tools.handleEnvelope(envelope(packet(0x55, PortNum.STORE_FORWARD_APP, StoreAndForward(
        rr: StoreAndForward_RequestResponse.ROUTER_HISTORY,
        history: StoreAndForward_History(historyMessages: 3),
      ).writeToBuffer())));
      expect(tools.lastRouterReply, 'Router is sending 3 stored messages.');

      tools.handleEnvelope(envelope(packet(0x55, PortNum.STORE_FORWARD_APP,
          StoreAndForward(rr: StoreAndForward_RequestResponse.ROUTER_BUSY).writeToBuffer())));
      expect(tools.lastRouterReply, contains('busy'));
    });

    test('encodes a history request in minutes to the router', () {
      final p = pb.ToRadio.fromBuffer(MeshtasticMeshTools.encodeHistoryRequest(0x55, const Duration(hours: 2))).packet;
      expect(p.to, 0x55);
      expect(p.decoded.portnum, PortNum.STORE_FORWARD_APP);
      final sf = StoreAndForward.fromBuffer(p.decoded.payload);
      expect(sf.rr, StoreAndForward_RequestResponse.CLIENT_HISTORY);
      expect(sf.history.window, 120);
    });

    test('ignores unrelated and malformed packets', () {
      expect(tools.handleEnvelope(envelope(packet(1, PortNum.TEXT_MESSAGE_APP, [104, 105]))), isFalse);
      expect(tools.handleEnvelope(Uint8List.fromList([0xff, 0xff])), isFalse);
    });
  });
}
