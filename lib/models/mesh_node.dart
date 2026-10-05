class MeshNode {
  const MeshNode({
    required this.number,
    this.name,
    this.lastHeard,
    this.battery,
    this.powered = false,
    this.snr,
    this.rssi,
    this.latitude,
    this.longitude,
    this.positionTime,
    this.hops,
    this.viaMqtt = false,
  });
  final int number;
  final String? name;
  final DateTime? lastHeard;
  final int? battery;
  final bool powered;
  final double? snr;
  final int? rssi;
  final double? latitude;
  final double? longitude;
  final DateTime? positionTime;
  final int? hops;
  final bool viaMqtt;
  String get id => '!${number.toRadixString(16).padLeft(8, '0')}';
  String get displayName => name == null || name!.isEmpty ? id : name!;
  bool get hasPosition => validPosition(latitude, longitude);

  static bool validPosition(double? lat, double? lon) =>
      lat != null &&
      lon != null &&
      lat.isFinite &&
      lon.isFinite &&
      lat.abs() <= 90 &&
      lon.abs() <= 180 &&
      !(lat == 0 && lon == 0);

  Map<String, dynamic> toJson() => {
    'number': number,
    'name': name,
    'heard': lastHeard?.toIso8601String(),
    'battery': battery,
    'powered': powered,
    'snr': snr != null && snr!.isFinite ? snr : null,
    'rssi': rssi,
    'lat': latitude,
    'lon': longitude,
    'positionTime': positionTime?.toIso8601String(),
    'hops': hops,
    'mqtt': viaMqtt,
  };
  factory MeshNode.fromJson(Map<String, dynamic> j) => MeshNode(
    number: j['number'] as int,
    name: j['name'] as String?,
    lastHeard: DateTime.tryParse(j['heard'] as String? ?? ''),
    battery: j['battery'] as int?,
    powered: j['powered'] == true,
    snr: (j['snr'] as num?)?.toDouble(),
    rssi: j['rssi'] as int?,
    latitude: (j['lat'] as num?)?.toDouble(),
    longitude: (j['lon'] as num?)?.toDouble(),
    positionTime: DateTime.tryParse(j['positionTime'] as String? ?? ''),
    hops: j['hops'] as int?,
    viaMqtt: j['mqtt'] == true,
  );
}
