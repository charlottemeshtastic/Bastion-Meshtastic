import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion_meshtastic/generated/meshtastic/channel.pb.dart';
import 'package:bastion_meshtastic/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion_meshtastic/models/chat_message.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'package:bastion_meshtastic/services/messaging/chat_history.dart';
import 'radio_session_test.dart' show FakeTransport;

class WriteTransport extends FakeTransport {
  bool reject = false;
  void Function(pb.ToRadio)? onWrite;
  @override
  Future<void> write(List<int> bytes) async {
    final packet = pb.ToRadio.fromBuffer(bytes);
    if (packet.hasPacket()) {
      if (reject) {
        throw StateError('Write interrupted');
      }
      onWrite?.call(packet);
    }
    writes.add(bytes);
  }
}

void main() {
  late RadioSession session;
  late WriteTransport transport;
  late StreamSubscription<ChatMessage> subscription;
  late List<ChatMessage> events;
  var id = 100;
  setUp(() async {
    id = 100;
    SharedPreferences.setMockInitialValues({});
    events = [];
    session = RadioSession(nonce: () => 123, packetId: () => ++id,
      ackTimeout: const Duration(milliseconds: 40));
    transport = WriteTransport();
    subscription = session.messages.listen(events.add);
    await session.connect(transport);
    transport.emit(pb.FromRadio(myInfo: pb.MyNodeInfo(myNodeNum: 42)));
    transport.emit(pb.FromRadio(channel: Channel(index: 0, role: Channel_Role.PRIMARY)));
    transport.emit(pb.FromRadio(configCompleteId: 123));
  });
  tearDown(() async {
    await session.disconnect();
    await subscription.cancel();
    session.dispose();
    await transport.finish();
  });
  void ack(int packetId, {int from = 7, pb.Routing_Error? reason}) {
    transport.emit(pb.FromRadio(packet: pb.MeshPacket(from: from, to: 42,
      decoded: pb.Data(portnum: PortNum.ROUTING_APP, requestId: packetId,
        payload: pb.Routing(errorReason: reason ?? pb.Routing_Error.NONE).writeToBuffer()))));
  }

  test('channel text serializes correctly and a radio write is not delivery', () async {
    await session.sendText('hello mesh', channel: 0);
    final packet = pb.ToRadio.fromBuffer(transport.writes.last).packet;
    expect(packet.to, ChatMessage.broadcast);
    expect(packet.channel, 0);
    expect(packet.wantAck, isTrue);
    expect(packet.decoded.portnum, PortNum.TEXT_MESSAGE_APP);
    expect(utf8.decode(packet.decoded.payload), 'hello mesh');
    expect(events.last.state, MessageState.written);
    ack(packet.id);
    expect(events.last.state, MessageState.acknowledged);
  });

  test('early acknowledgement cannot be downgraded by completing the BLE write', () async {
    transport.onWrite = (frame) => ack(frame.packet.id);
    await session.sendText('test', channel: 0, destination: 7);
    expect(events.last.state, MessageState.acknowledged);
    expect(events.where((e) => e.state == MessageState.written), isEmpty);
  });

  test('direct messages target a node and ignore unrelated acknowledgements', () async {
    await session.sendText('direct', channel: 0, destination: 7);
    final packet = pb.ToRadio.fromBuffer(transport.writes.last).packet;
    expect(packet.to, 7);
    ack(packet.id, from: 8);
    expect(events.last.state, MessageState.written);
    ack(packet.id, reason: pb.Routing_Error.NO_ROUTE);
    expect(events.last.state, MessageState.failed);
    expect(events.last.detail, 'NO_ROUTE');
  });

  test('UTF-8 limit, empty text and disabled channel never transmit', () async {
    final count = transport.writes.length;
    await expectLater(session.sendText('😀' * 59, channel: 0), throwsArgumentError);
    await expectLater(session.sendText('  ', channel: 0), throwsArgumentError);
    await expectLater(session.sendText('hello', channel: 5), throwsStateError);
    expect(transport.writes.length, count);
    expect(events, isEmpty);
  });

  test('incoming text deduplicates and rejects messages addressed to someone else', () {
    pb.MeshPacket text(int to, int id) => pb.MeshPacket(from: 7, to: to, id: id,
      channel: 0, decoded: pb.Data(portnum: PortNum.TEXT_MESSAGE_APP, payload: utf8.encode('hello')));
    transport.emit(pb.FromRadio(packet: text(42, 22)));
    transport.emit(pb.FromRadio(packet: text(42, 22)));
    transport.emit(pb.FromRadio(packet: text(8, 23)));
    expect(events, hasLength(1));
    expect(events.single.isDirect, isTrue);
    expect(events.single.peer, 7);
  });

  test('write failure and disconnect remain unconfirmed without automatic retry', () async {
    transport.reject = true;
    await expectLater(session.sendText('hello', channel: 0), throwsStateError);
    expect(events.last.state, MessageState.unknown);
    transport.reject = false;
    await session.sendText('next', channel: 0);
    final count = transport.writes.length;
    await session.disconnect();
    expect(events.last.state, MessageState.unknown);
    expect(transport.writes.length, count);
  });

  test('ack timeout becomes unconfirmed instead of falsely delivered', () async {
    await session.sendText('hello', channel: 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events.last.state, MessageState.unknown);
  });

  test('radio queue rejection updates the correct message', () async {
    await session.sendText('hello', channel: 0);
    final packet = pb.ToRadio.fromBuffer(transport.writes.last).packet;
    transport.emit(pb.FromRadio(queueStatus: pb.QueueStatus(meshPacketId: packet.id, res: 1)));
    expect(events.last.state, MessageState.failed);
  });

  test('history survives restart, scopes radios and recovers unresolved sends', () async {
    final history = ChatHistory();
    await history.load();
    final eventSub = session.messages.listen(history.upsert);
    await session.sendText('saved', channel: 0);
    await history.saved;
    final restored = ChatHistory();
    await restored.load();
    expect(restored.messages.single.text, 'saved');
    expect(restored.messages.single.radio, 42);
    expect(restored.messages.single.state, MessageState.unknown);
    await restored.saved;
    await eventSub.cancel();
    history.dispose();
    restored.dispose();
  });
}
