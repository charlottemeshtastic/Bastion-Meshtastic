import 'dart:async';
import 'dart:typed_data';

import 'package:geolocator/geolocator.dart' hide Position;

import '../generated/meshtastic/mesh.pb.dart';
import '../generated/meshtastic/portnums.pbenum.dart';
import 'bastion_geo.dart';

/// One location fix from the phone.
class PhoneFix {
  const PhoneFix({
    required this.latitude,
    required this.longitude,
    required this.time,
    this.altitudeMeters,
  });

  final double latitude;
  final double longitude;
  final DateTime time;
  final double? altitudeMeters;
}

/// Phone location, behind an interface so sharing logic is testable.
abstract interface class PhoneLocationSource {
  /// Returns null when location can be used, otherwise why not.
  Future<String?> ensureAccess();

  Stream<PhoneFix> watch();
}

class GeolocatorLocationSource implements PhoneLocationSource {
  @override
  Future<String?> ensureAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Turn on location services on this phone.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always || LocationPermission.whileInUse => null,
      LocationPermission.deniedForever =>
        'Location permission is blocked. Allow it for Bastion in Android settings.',
      _ => 'Location permission was not granted.',
    };
  }

  @override
  Stream<PhoneFix> watch() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).map((p) => PhoneFix(
            latitude: p.latitude,
            longitude: p.longitude,
            altitudeMeters: p.altitude,
            time: p.timestamp,
          ));
}

/// Sends the phone's location to the connected radio, which broadcasts it to
/// the mesh as its own position (when the radio has no GPS of its own).
///
/// Throttled: at most one update per [minInterval], plus one whenever the
/// phone moves more than [minDistanceMeters] after [movingInterval].
class BastionPhonePositionSharer {
  BastionPhonePositionSharer({
    required this.source,
    required this.send,
    required this.localNodeNum,
    this.minInterval = const Duration(minutes: 5),
    this.movingInterval = const Duration(seconds: 30),
    this.minDistanceMeters = 50,
  });

  final PhoneLocationSource source;
  final Future<void> Function(Uint8List toRadio) send;
  final int localNodeNum;
  final Duration minInterval;
  final Duration movingInterval;
  final double minDistanceMeters;

  StreamSubscription<PhoneFix>? _subscription;
  PhoneFix? _lastSent;

  DateTime? get lastSentAt => _lastSent?.time;
  bool get isRunning => _subscription != null;

  /// Starts sharing. Returns an error message when location is unavailable.
  Future<String?> start() async {
    if (_subscription != null) return null;
    final problem = await source.ensureAccess();
    if (problem != null) return problem;
    _subscription = source.watch().listen(
      (fix) => unawaited(handleFix(fix)),
      onError: (Object _) {},
    );
    return null;
  }

  /// Sends [fix] if the throttle allows it. Public for tests.
  Future<void> handleFix(PhoneFix fix) async {
    final last = _lastSent;
    if (last != null) {
      final elapsed = fix.time.difference(last.time);
      final moved = BastionGeo.distanceMeters(
          last.latitude, last.longitude, fix.latitude, fix.longitude);
      final due = elapsed >= minInterval ||
          (moved >= minDistanceMeters && elapsed >= movingInterval);
      if (!due) return;
    }
    _lastSent = fix;
    await send(encode(fix, localNodeNum));
  }

  static Uint8List encode(PhoneFix fix, int localNodeNum) => ToRadio(
        packet: MeshPacket(
          to: localNodeNum,
          decoded: Data(
            portnum: PortNum.POSITION_APP,
            payload: Position(
              latitudeI: (fix.latitude * 1e7).round(),
              longitudeI: (fix.longitude * 1e7).round(),
              altitude: fix.altitudeMeters?.round(),
              time: fix.time.millisecondsSinceEpoch ~/ 1000,
              locationSource: Position_LocSource.LOC_EXTERNAL,
            ).writeToBuffer(),
          ),
        ),
      ).writeToBuffer();

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
