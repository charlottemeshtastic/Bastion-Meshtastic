import 'dart:math';
import '../models/mesh_node.dart';

/// Great-circle geometry, not a terrain/coverage or connectivity prediction.
({double km, double bearing})? nodeDistance(MeshNode a, MeshNode b) {
  if (!a.hasPosition || !b.hasPosition) {
    return null;
  }
  final lat1 = a.latitude! * pi / 180;
  final lat2 = b.latitude! * pi / 180;
  final dLat = lat2 - lat1;
  final dLon = (b.longitude! - a.longitude!) * pi / 180;
  final h =
      pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
  final km = 6371.0088 * 2 * asin(sqrt(h.clamp(0, 1)));
  final bearing =
      (atan2(
                sin(dLon) * cos(lat2),
                cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon),
              ) *
              180 /
              pi +
          360) %
      360;
  return (km: km, bearing: bearing);
}
