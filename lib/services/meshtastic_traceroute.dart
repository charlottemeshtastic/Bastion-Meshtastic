import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';

import '../generated/meshtastic/mesh.pb.dart';
import '../generated/meshtastic/portnums.pbenum.dart';

/// One hop of a traceroute: the node reached and the SNR it heard us at.
class TracerouteHop {
  const TracerouteHop(this.nodeNum, this.snrDb);

  final int nodeNum;

  /// Null when the firmware did not record a value for this hop.
  final double? snrDb;
}

class TracerouteResult {
  const TracerouteResult({required this.towards, required this.back});

  /// From the first relay to the destination. The local node is implied.
  final List<TracerouteHop> towards;

  /// From the destination's first relay back to the local node. Empty when
  /// the firmware is too old to report the return path.
  final List<TracerouteHop> back;

  /// Relays between the local node and the destination, excluding both.
  int get intermediateHops => towards.length - 1;
}

class MeshtasticTracerouteException implements Exception {
  MeshtasticTracerouteException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Sends TRACEROUTE_APP requests and matches the RouteDiscovery reply.
///
/// Firmware rate-limits traceroutes; callers should not retry quickly.
class MeshtasticTraceroute {
  MeshtasticTraceroute({
    required Stream<Uint8List> incoming,
    required Future<void> Function(Uint8List toRadio) send,
    required this.localNodeNum,
    Random? random,
  })  : _send = send,
        _random = random ?? Random.secure() {
    _subscription = incoming.listen(_handleEnvelope);
  }

  /// RouteDiscovery marks a hop with no recorded SNR with INT8_MIN.
  static const _unknownSnr = -128;

  final int localNodeNum;
  final Future<void> Function(Uint8List) _send;
  final Random _random;
  final Map<int, Completer<TracerouteResult>> _pending = {};
  late final StreamSubscription<Uint8List> _subscription;

  bool get isRunning => _pending.isNotEmpty;

  Future<TracerouteResult> trace(
    int destination, {
    int channel = 0,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (destination == localNodeNum) {
      throw ArgumentError.value(destination, 'destination', 'is the local node');
    }
    final id = _random.nextInt(0x7fffffff) + 1;
    final completer = Completer<TracerouteResult>();
    _pending[id] = completer;
    final envelope = ToRadio(
      packet: MeshPacket(
        to: destination,
        id: id,
        channel: channel,
        wantAck: true,
        decoded: Data(
          portnum: PortNum.TRACEROUTE_APP,
          payload: RouteDiscovery().writeToBuffer(),
          wantResponse: true,
        ),
      ),
    );
    try {
      await _send(envelope.writeToBuffer());
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw MeshtasticTracerouteException(
          'No route reply within ${timeout.inSeconds} s. '
          'The node may be out of range or asleep.',
        ),
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _handleEnvelope(Uint8List bytes) {
    final MeshPacket packet;
    try {
      final envelope = FromRadio.fromBuffer(bytes);
      if (!envelope.hasPacket() || !envelope.packet.hasDecoded()) return;
      packet = envelope.packet;
    } on InvalidProtocolBufferException {
      return;
    }
    final data = packet.decoded;
    final completer = _pending[data.requestId];
    if (completer == null || completer.isCompleted) return;

    if (data.portnum == PortNum.TRACEROUTE_APP) {
      try {
        completer.complete(_parse(RouteDiscovery.fromBuffer(data.payload), packet.from));
      } on InvalidProtocolBufferException {
        completer.completeError(MeshtasticTracerouteException('Malformed route reply.'));
      }
    } else if (data.portnum == PortNum.ROUTING_APP) {
      try {
        final routing = Routing.fromBuffer(data.payload);
        if (routing.whichVariant() == Routing_Variant.errorReason &&
            routing.errorReason != Routing_Error.NONE) {
          completer.completeError(MeshtasticTracerouteException(
            'Traceroute failed: ${routing.errorReason.name}.',
          ));
        }
      } on InvalidProtocolBufferException {
        // Ignore malformed routing frames; the timeout still applies.
      }
    }
  }

  TracerouteResult _parse(RouteDiscovery reply, int destination) {
    List<TracerouteHop> hops(List<int> relays, List<int> snrs, int last) => [
          for (var i = 0; i <= relays.length; i++)
            TracerouteHop(
              i < relays.length ? relays[i] : last,
              i < snrs.length && snrs[i] != _unknownSnr ? snrs[i] / 4 : null,
            ),
        ];
    return TracerouteResult(
      towards: hops(reply.route, reply.snrTowards, destination),
      back: reply.snrBack.isEmpty && reply.routeBack.isEmpty
          ? const []
          : hops(reply.routeBack, reply.snrBack, localNodeNum),
    );
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(MeshtasticTracerouteException('Radio disconnected.'));
      }
    }
    _pending.clear();
  }
}
