class MeshNode {
  const MeshNode({required this.number, this.name, this.lastHeard,
    this.battery, this.powered = false, this.snr, this.rssi,
    this.latitude, this.longitude, this.hops, this.viaMqtt = false});
  final int number;
  final String? name;
  final DateTime? lastHeard;
  final int? battery;
  final bool powered;
  final double? snr;
  final int? rssi;
  final double? latitude;
  final double? longitude;
  final int? hops;
  final bool viaMqtt;
  String get id => '!${number.toRadixString(16).padLeft(8, '0')}';
  String get displayName => name == null || name!.isEmpty ? id : name!;
}
