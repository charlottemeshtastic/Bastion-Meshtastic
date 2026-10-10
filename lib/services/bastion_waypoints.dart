import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../generated/meshtastic/mesh.pb.dart' as pb;
import '../generated/meshtastic/portnums.pbenum.dart';
import 'meshtastic_text_codec.dart';

/// A Meshtastic waypoint shared on a channel.
class MeshWaypoint {
  const MeshWaypoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.name,
    this.description = '',
    this.icon,
    this.expires,
    this.lockedTo = 0,
    this.from,
  });

  final int id;
  final double latitude;
  final double longitude;
  final String name;
  final String description;

  /// Unicode code point of the emoji shown on the map, if any.
  final int? icon;

  /// Null when the waypoint never expires.
  final DateTime? expires;

  /// Node allowed to edit or delete it; 0 means anyone.
  final int lockedTo;

  /// Node that sent it, when received over the mesh.
  final int? from;

  String get iconText => icon == null ? '📍' : String.fromCharCode(icon!);

  bool isExpired(DateTime now) => expires != null && !expires!.isAfter(now);

  Map<String, Object?> toJson() => {
        'id': id,
        'lat': latitude,
        'lon': longitude,
        'name': name,
        'description': description,
        'icon': icon,
        'expires': expires?.millisecondsSinceEpoch,
        'lockedTo': lockedTo,
        'from': from,
      };

  static MeshWaypoint fromJson(Map<String, Object?> json) => MeshWaypoint(
        id: json['id']! as int,
        latitude: (json['lat']! as num).toDouble(),
        longitude: (json['lon']! as num).toDouble(),
        name: json['name']! as String,
        description: json['description'] as String? ?? '',
        icon: json['icon'] as int?,
        expires: json['expires'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['expires']! as int, isUtc: true),
        lockedTo: json['lockedTo'] as int? ?? 0,
        from: json['from'] as int?,
      );
}

/// Keeps the waypoints heard on the mesh, persisted on the phone.
class BastionWaypointStore {
  BastionWaypointStore({DateTime Function()? clock, SharedPreferencesAsync? preferences})
      : _clock = clock ?? DateTime.now,
        _preferences = preferences;

  static const _key = 'bastion.waypoints';

  /// Firmware limits, from the Waypoint protobuf options.
  static const maxNameLength = 30;
  static const maxDescriptionLength = 100;

  final DateTime Function() _clock;
  SharedPreferencesAsync? _preferences;
  final Map<int, MeshWaypoint> _waypoints = {};

  List<MeshWaypoint> get waypoints {
    final now = _clock();
    _waypoints.removeWhere((_, w) => w.isExpired(now));
    return List.unmodifiable(_waypoints.values);
  }

  Future<void> load() async {
    try {
      final raw = await (_preferences ??= SharedPreferencesAsync()).getString(_key);
      if (raw == null) return;
      for (final item in jsonDecode(raw) as List<Object?>) {
        final waypoint = MeshWaypoint.fromJson((item! as Map).cast<String, Object?>());
        _waypoints[waypoint.id] = waypoint;
      }
    } catch (_) {
      // A damaged store is ignored rather than blocking the app.
    }
  }

  Future<void> _save() async {
    try {
      await (_preferences ??= SharedPreferencesAsync())
          .setString(_key, jsonEncode([for (final w in waypoints) w.toJson()]));
    } catch (_) {
      // Persistence is best effort.
    }
  }

  /// Applies a WAYPOINT_APP packet. Returns true when the store changed.
  Future<bool> handlePacket(pb.MeshPacket packet) async {
    if (!packet.hasDecoded() || packet.decoded.portnum != PortNum.WAYPOINT_APP) return false;
    final pb.Waypoint proto;
    try {
      proto = pb.Waypoint.fromBuffer(packet.decoded.payload);
    } on InvalidProtocolBufferException {
      return false;
    }
    return apply(fromProto(proto, from: packet.from));
  }

  /// Adds, updates or (when expired) removes [waypoint].
  Future<bool> apply(MeshWaypoint waypoint) async {
    if (waypoint.isExpired(_clock())) {
      if (_waypoints.remove(waypoint.id) == null) return false;
    } else {
      _waypoints[waypoint.id] = waypoint;
    }
    await _save();
    return true;
  }

  static MeshWaypoint fromProto(pb.Waypoint w, {int? from}) => MeshWaypoint(
        id: w.id,
        latitude: w.latitudeI / 1e7,
        longitude: w.longitudeI / 1e7,
        name: w.name,
        description: w.description,
        icon: w.icon == 0 ? null : w.icon,
        expires: w.expire == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(w.expire * 1000, isUtc: true),
        lockedTo: w.lockedTo,
        from: from,
      );

  static pb.Waypoint toProto(MeshWaypoint w) => pb.Waypoint(
        id: w.id,
        latitudeI: (w.latitude * 1e7).round(),
        longitudeI: (w.longitude * 1e7).round(),
        name: w.name,
        description: w.description,
        icon: w.icon,
        expire: w.expires == null ? 0 : w.expires!.millisecondsSinceEpoch ~/ 1000,
        lockedTo: w.lockedTo,
      );

  /// Broadcast envelope for [waypoint] on [channel].
  static Uint8List encode(MeshWaypoint waypoint, {int channel = 0}) => pb.ToRadio(
        packet: pb.MeshPacket(
          to: MeshtasticTextCodec.broadcastNode,
          channel: channel,
          decoded: pb.Data(
            portnum: PortNum.WAYPOINT_APP,
            payload: toProto(waypoint).writeToBuffer(),
          ),
        ),
      ).writeToBuffer();

  /// A deletion is the same waypoint re-sent already expired, as the official
  /// apps do.
  static MeshWaypoint deletion(MeshWaypoint waypoint) => MeshWaypoint(
        id: waypoint.id,
        latitude: waypoint.latitude,
        longitude: waypoint.longitude,
        name: waypoint.name,
        description: waypoint.description,
        icon: waypoint.icon,
        expires: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        lockedTo: waypoint.lockedTo,
      );

  static int newId([Random? random]) => (random ?? Random.secure()).nextInt(0x7fffffff) + 1;
}
