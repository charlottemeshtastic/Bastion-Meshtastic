import 'dart:async';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';

import '../generated/meshtastic/mesh.pb.dart' as pb;
import '../generated/meshtastic/portnums.pbenum.dart';
import 'meshtastic_radio_session.dart';

class MeshtasticNode {
  const MeshtasticNode({
    required this.num,
    this.id,
    this.longName,
    this.shortName,
    this.hardwareModel,
    this.latitude,
    this.longitude,
    this.altitudeMeters,
    this.positionTime,
    this.lastHeard,
    this.snr,
    this.hopsAway,
    this.batteryLevel,
  });

  final int num;
  final String? id;
  final String? longName;
  final String? shortName;
  final int? hardwareModel;

  /// Degrees, WGS84. Both null when the node has not reported a position.
  final double? latitude;
  final double? longitude;
  final int? altitudeMeters;

  /// When the position was taken, as reported by the node.
  final DateTime? positionTime;

  /// When the radio last heard any packet from this node.
  final DateTime? lastHeard;

  /// SNR in dB of the last packet heard directly.
  final double? snr;
  final int? hopsAway;

  /// 0–100, or 101 when the node is powered externally.
  final int? batteryLevel;

  bool get hasPosition => latitude != null && longitude != null;

  String get displayName => (longName?.isNotEmpty ?? false)
      ? longName!
      : (id ?? '!${num.toRadixString(16).padLeft(8, '0')}');

  MeshtasticNode _copy({
    String? id,
    String? longName,
    String? shortName,
    int? hardwareModel,
    double? latitude,
    double? longitude,
    int? altitudeMeters,
    DateTime? positionTime,
    DateTime? lastHeard,
    double? snr,
  }) =>
      MeshtasticNode(
        num: num,
        id: id ?? this.id,
        longName: longName ?? this.longName,
        shortName: shortName ?? this.shortName,
        hardwareModel: hardwareModel ?? this.hardwareModel,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        altitudeMeters: altitudeMeters ?? this.altitudeMeters,
        positionTime: positionTime ?? this.positionTime,
        lastHeard: lastHeard ?? this.lastHeard,
        snr: snr ?? this.snr,
        hopsAway: hopsAway,
        batteryLevel: batteryLevel,
      );
}

/// Tracks every node the radio reports, plus live updates from the mesh.
///
/// The initial node list comes from NodeInfo during the handshake. After
/// that, position and node-info packets update nodes in place. [nodeUpdates]
/// fires only for identity updates, not for every packet heard.
class MeshtasticNodeDatabase {
  MeshtasticNodeDatabase(this.session, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final MeshtasticRadioSession session;
  final DateTime Function() _clock;
  final Map<int, MeshtasticNode> _nodes = {};
  final StreamController<List<MeshtasticNode>> _changes =
      StreamController<List<MeshtasticNode>>.broadcast();
  final StreamController<MeshtasticNode> _nodeUpdates =
      StreamController<MeshtasticNode>.broadcast();
  StreamSubscription<Uint8List>? _subscription;

  List<MeshtasticNode> get nodes {
    final values = _nodes.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return List.unmodifiable(values);
  }

  Stream<List<MeshtasticNode>> get changes => _changes.stream;
  Stream<MeshtasticNode> get nodeUpdates => _nodeUpdates.stream;

  Future<void> start() async {
    await _subscription?.cancel();
    _subscription = session.incomingEnvelopes.listen(handleEnvelope);
  }

  /// Applies one FromRadio envelope. Public for tests.
  void handleEnvelope(Uint8List bytes) {
    final pb.FromRadio envelope;
    try {
      envelope = pb.FromRadio.fromBuffer(bytes);
    } on InvalidProtocolBufferException {
      return;
    }
    if (envelope.hasNodeInfo()) {
      if (!envelope.nodeInfo.hasNum()) return;
      _store(MeshtasticNodeInfoCodec.fromProto(envelope.nodeInfo), identity: true);
    } else if (envelope.hasPacket() && envelope.packet.hasDecoded()) {
      _handlePacket(envelope.packet);
    }
  }

  void _handlePacket(pb.MeshPacket packet) {
    final from = packet.from;
    if (from == 0) return;
    var node = (_nodes[from] ?? MeshtasticNode(num: from))._copy(
      lastHeard: _clock(),
      snr: packet.rxSnr != 0 ? packet.rxSnr : null,
    );
    var identity = false;
    final data = packet.decoded;
    try {
      if (data.portnum == PortNum.POSITION_APP) {
        node = MeshtasticNodeInfoCodec.applyPosition(node, pb.Position.fromBuffer(data.payload));
      } else if (data.portnum == PortNum.NODEINFO_APP) {
        node = MeshtasticNodeInfoCodec.applyUser(node, pb.User.fromBuffer(data.payload));
        identity = true;
      }
    } on InvalidProtocolBufferException {
      // Keep the last-heard update; ignore the malformed payload.
    }
    _store(node, identity: identity);
  }

  void _store(MeshtasticNode node, {required bool identity}) {
    _nodes[node.num] = node;
    if (identity) _nodeUpdates.add(node);
    _changes.add(nodes);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _changes.close();
    await _nodeUpdates.close();
  }
}

abstract final class MeshtasticNodeInfoCodec {
  static MeshtasticNode decode(Uint8List bytes) {
    final pb.NodeInfo info;
    try {
      info = pb.NodeInfo.fromBuffer(bytes);
    } on InvalidProtocolBufferException catch (error) {
      throw FormatException('Malformed NodeInfo: ${error.message}');
    }
    if (!info.hasNum()) {
      throw const FormatException('NodeInfo is missing node number.');
    }
    return fromProto(info);
  }

  static MeshtasticNode fromProto(pb.NodeInfo info) {
    var node = MeshtasticNode(
      num: info.num,
      lastHeard: info.lastHeard == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(info.lastHeard * 1000, isUtc: true),
      snr: info.hasSnr() ? info.snr : null,
      hopsAway: info.hasHopsAway() ? info.hopsAway : null,
      batteryLevel: info.hasDeviceMetrics() && info.deviceMetrics.hasBatteryLevel()
          ? info.deviceMetrics.batteryLevel
          : null,
    );
    if (info.hasUser()) node = applyUser(node, info.user);
    if (info.hasPosition()) node = applyPosition(node, info.position);
    return node;
  }

  static MeshtasticNode applyUser(MeshtasticNode node, pb.User user) => node._copy(
        id: user.id.isEmpty ? null : user.id,
        longName: user.longName.isEmpty ? null : user.longName,
        shortName: user.shortName.isEmpty ? null : user.shortName,
        hardwareModel: user.hasHwModel() ? user.hwModel.value : null,
      );

  /// Ignores positions without coordinates and the 0,0 "no fix" value.
  static MeshtasticNode applyPosition(MeshtasticNode node, pb.Position position) {
    if (!position.hasLatitudeI() || !position.hasLongitudeI()) return node;
    final lat = position.latitudeI / 1e7;
    final lon = position.longitudeI / 1e7;
    if ((lat == 0 && lon == 0) || lat.abs() > 90 || lon.abs() > 180) return node;
    return node._copy(
      latitude: lat,
      longitude: lon,
      altitudeMeters: position.hasAltitude() ? position.altitude : null,
      positionTime: position.time == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(position.time * 1000, isUtc: true),
    );
  }
}
