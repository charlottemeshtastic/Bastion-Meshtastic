import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';

import '../generated/meshtastic/mesh.pb.dart' as pb;
import '../generated/meshtastic/portnums.pbenum.dart';
import '../generated/meshtastic/storeforward.pb.dart';

/// One packet heard from a node running the Range Test module as sender.
class RangeTestEntry {
  const RangeTestEntry({
    required this.from,
    required this.text,
    required this.receivedAt,
    this.snr,
    this.rssi,
  });

  final int from;

  /// Usually "seq N"; a gap in N means packets were lost.
  final String text;
  final DateTime receivedAt;
  final double? snr;
  final int? rssi;
}

/// A node running Store & Forward as a server, known from its heartbeat.
class StoreForwardRouter {
  const StoreForwardRouter({required this.nodeNum, required this.lastHeard, this.heartbeatSecs});

  final int nodeNum;
  final DateTime lastHeard;
  final int? heartbeatSecs;
}

/// Listens for Range Test and Store & Forward traffic.
class MeshtasticMeshTools {
  MeshtasticMeshTools({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const maxRangeTestEntries = 500;

  final DateTime Function() _clock;
  final List<RangeTestEntry> _rangeTest = [];
  final Map<int, StoreForwardRouter> _routers = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Latest router reply to a history request, for user feedback.
  String? lastRouterReply;

  List<RangeTestEntry> get rangeTest => List.unmodifiable(_rangeTest);
  List<StoreForwardRouter> get routers => List.unmodifiable(_routers.values);
  Stream<void> get changes => _changes.stream;

  void clearRangeTest() {
    _rangeTest.clear();
    _changes.add(null);
  }

  /// Applies one FromRadio envelope. Returns true when something changed.
  bool handleEnvelope(Uint8List bytes) {
    final pb.MeshPacket packet;
    try {
      final envelope = pb.FromRadio.fromBuffer(bytes);
      if (!envelope.hasPacket() || !envelope.packet.hasDecoded()) return false;
      packet = envelope.packet;
    } on InvalidProtocolBufferException {
      return false;
    }
    final data = packet.decoded;
    if (data.portnum == PortNum.RANGE_TEST_APP) {
      _rangeTest.add(RangeTestEntry(
        from: packet.from,
        text: utf8.decode(data.payload, allowMalformed: true),
        receivedAt: _clock(),
        snr: packet.rxSnr == 0 ? null : packet.rxSnr,
        rssi: packet.rxRssi == 0 ? null : packet.rxRssi,
      ));
      if (_rangeTest.length > maxRangeTestEntries) _rangeTest.removeAt(0);
      _changes.add(null);
      return true;
    }
    if (data.portnum != PortNum.STORE_FORWARD_APP) return false;
    final StoreAndForward sf;
    try {
      sf = StoreAndForward.fromBuffer(data.payload);
    } on InvalidProtocolBufferException {
      return false;
    }
    switch (sf.rr) {
      case StoreAndForward_RequestResponse.ROUTER_HEARTBEAT:
        _routers[packet.from] = StoreForwardRouter(
          nodeNum: packet.from,
          lastHeard: _clock(),
          heartbeatSecs: sf.hasHeartbeat() && sf.heartbeat.period != 0 ? sf.heartbeat.period : null,
        );
      case StoreAndForward_RequestResponse.ROUTER_HISTORY:
        final count = sf.hasHistory() ? sf.history.historyMessages : 0;
        _routers.putIfAbsent(packet.from, () => StoreForwardRouter(nodeNum: packet.from, lastHeard: _clock()));
        lastRouterReply = count == 0
            ? 'Router has no stored messages for that window.'
            : 'Router is sending $count stored message${count == 1 ? '' : 's'}.';
      case StoreAndForward_RequestResponse.ROUTER_BUSY:
        lastRouterReply = 'Router is busy. Try again in a minute.';
      case StoreAndForward_RequestResponse.ROUTER_ERROR:
        lastRouterReply = 'Router reported an error.';
      default:
        return false;
    }
    _changes.add(null);
    return true;
  }

  /// Asks [router] to replay messages from the last [window].
  static Uint8List encodeHistoryRequest(int router, Duration window) => pb.ToRadio(
        packet: pb.MeshPacket(
          to: router,
          wantAck: true,
          decoded: pb.Data(
            portnum: PortNum.STORE_FORWARD_APP,
            payload: StoreAndForward(
              rr: StoreAndForward_RequestResponse.CLIENT_HISTORY,
              // The firmware reads the window in minutes.
              history: StoreAndForward_History(window: window.inMinutes),
            ).writeToBuffer(),
          ),
        ),
      ).writeToBuffer();

  Future<void> dispose() => _changes.close();
}
