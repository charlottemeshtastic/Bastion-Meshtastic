import 'dart:async';
import 'dart:typed_data';

import 'package:bastion/generated/meshtastic/mesh.pb.dart';
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/services/bastion_phone_position.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSource implements PhoneLocationSource {
  _FakeSource({this.problem});

  final String? problem;
  final fixes = StreamController<PhoneFix>.broadcast();

  @override
  Future<String?> ensureAccess() async => problem;

  @override
  Stream<PhoneFix> watch() => fixes.stream;
}

PhoneFix fix(double lat, double lon, int minute, {int second = 0}) => PhoneFix(
      latitude: lat,
      longitude: lon,
      altitudeMeters: 412.6,
      time: DateTime.utc(2026, 10, 9, 12, minute, second),
    );

void main() {
  late List<Uint8List> sent;
  late BastionPhonePositionSharer sharer;

  setUp(() {
    sent = [];
    sharer = BastionPhonePositionSharer(
      source: _FakeSource(),
      send: (bytes) async => sent.add(bytes),
      localNodeNum: 0x1234,
    );
  });

  test('encodes a local POSITION_APP packet from the phone', () async {
    await sharer.handleFix(fix(35.5, -83.25, 0));
    final packet = ToRadio.fromBuffer(sent.single).packet;
    expect(packet.to, 0x1234);
    expect(packet.decoded.portnum, PortNum.POSITION_APP);
    final position = Position.fromBuffer(packet.decoded.payload);
    expect(position.latitudeI, 355000000);
    expect(position.longitudeI, -832500000);
    expect(position.altitude, 413);
    expect(position.locationSource, Position_LocSource.LOC_EXTERNAL);
  });

  test('throttles stationary fixes to one per 5 minutes', () async {
    await sharer.handleFix(fix(35.5, -83.25, 0));
    await sharer.handleFix(fix(35.5, -83.25, 2));
    await sharer.handleFix(fix(35.50001, -83.25, 4));
    expect(sent, hasLength(1));
    await sharer.handleFix(fix(35.5, -83.25, 5));
    expect(sent, hasLength(2));
  });

  test('sends sooner after moving more than 50 m', () async {
    await sharer.handleFix(fix(35.5, -83.25, 0));
    await sharer.handleFix(fix(35.501, -83.25, 0, second: 10));
    expect(sent, hasLength(1), reason: 'too soon even though moved');
    await sharer.handleFix(fix(35.501, -83.25, 0, second: 40));
    expect(sent, hasLength(2));
  });

  test('reports why location cannot be used and does not start', () async {
    final blocked = BastionPhonePositionSharer(
      source: _FakeSource(problem: 'Location permission was not granted.'),
      send: (_) async {},
      localNodeNum: 1,
    );
    expect(await blocked.start(), 'Location permission was not granted.');
    expect(blocked.isRunning, isFalse);
  });
}
