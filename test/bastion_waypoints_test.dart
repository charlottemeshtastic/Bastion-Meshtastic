import 'package:bastion/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/services/bastion_waypoints.dart';
import 'package:bastion/services/meshtastic_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final now = DateTime.utc(2026, 10, 10, 12);

pb.MeshPacket waypointPacket(pb.Waypoint waypoint, {int from = 0x77}) => pb.MeshPacket(
      from: from,
      decoded: pb.Data(portnum: PortNum.WAYPOINT_APP, payload: waypoint.writeToBuffer()),
    );

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  test('stores a received waypoint with sender, icon and expiry', () async {
    final store = BastionWaypointStore(clock: () => now);
    final changed = await store.handlePacket(waypointPacket(pb.Waypoint(
      id: 9,
      latitudeI: 355000000,
      longitudeI: -832500000,
      name: 'Camp',
      description: 'Flat ground',
      icon: '⛺'.runes.first,
      expire: now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
    )));
    expect(changed, isTrue);
    final w = store.waypoints.single;
    expect(w.name, 'Camp');
    expect(w.latitude, 35.5);
    expect(w.iconText, '⛺');
    expect(w.from, 0x77);
    expect(w.expires, now.add(const Duration(hours: 2)));
  });

  test('an expired copy deletes the waypoint', () async {
    final store = BastionWaypointStore(clock: () => now);
    await store.handlePacket(waypointPacket(pb.Waypoint(id: 9, latitudeI: 1, longitudeI: 1, name: 'A')));
    final deletion = BastionWaypointStore.deletion(store.waypoints.single);
    await store.handlePacket(waypointPacket(BastionWaypointStore.toProto(deletion)));
    expect(store.waypoints, isEmpty);
  });

  test('waypoints past their expiry disappear', () async {
    var clock = now;
    final store = BastionWaypointStore(clock: () => clock);
    await store.apply(MeshWaypoint(
      id: 1, latitude: 1, longitude: 1, name: 'Soon', expires: now.add(const Duration(minutes: 5))));
    expect(store.waypoints, hasLength(1));
    clock = now.add(const Duration(minutes: 6));
    expect(store.waypoints, isEmpty);
  });

  test('persists across store instances', () async {
    final first = BastionWaypointStore(clock: () => now);
    await first.apply(const MeshWaypoint(id: 3, latitude: 10, longitude: 20, name: 'Trailhead', icon: 0x1F6A9));
    final second = BastionWaypointStore(clock: () => now);
    await second.load();
    expect(second.waypoints.single.name, 'Trailhead');
    expect(second.waypoints.single.iconText, '🚩');
  });

  test('encodes a broadcast WAYPOINT_APP packet', () {
    final bytes = BastionWaypointStore.encode(
      const MeshWaypoint(id: 5, latitude: 1.5, longitude: -2.25, name: 'Water', lockedTo: 0x42),
      channel: 1,
    );
    final packet = pb.ToRadio.fromBuffer(bytes).packet;
    expect(packet.to, MeshtasticTextCodec.broadcastNode);
    expect(packet.channel, 1);
    expect(packet.decoded.portnum, PortNum.WAYPOINT_APP);
    final waypoint = pb.Waypoint.fromBuffer(packet.decoded.payload);
    expect(waypoint.latitudeI, 15000000);
    expect(waypoint.longitudeI, -22500000);
    expect(waypoint.lockedTo, 0x42);
    expect(waypoint.expire, 0);
  });

  test('ignores other ports', () async {
    final store = BastionWaypointStore(clock: () => now);
    final changed = await store.handlePacket(pb.MeshPacket(
      from: 1,
      decoded: pb.Data(portnum: PortNum.TEXT_MESSAGE_APP, payload: [1, 2]),
    ));
    expect(changed, isFalse);
  });
}
