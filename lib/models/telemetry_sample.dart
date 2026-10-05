/// Values actually present in one received packet. Missing values stay missing.
class TelemetrySample {
  const TelemetrySample({
    required this.radio,
    required this.node,
    required this.time,
    this.battery,
    this.powered,
    this.voltage,
    this.snr,
    this.rssi,
    this.channelUtilization,
    this.airUtilization,
  });
  final int radio;
  final int node;
  final DateTime time;
  final int? battery;
  final bool? powered;
  final double? voltage;
  final double? snr;
  final int? rssi;
  final double? channelUtilization;
  final double? airUtilization;
  bool get hasValues =>
      battery != null ||
      powered != null ||
      voltage != null ||
      snr != null ||
      rssi != null ||
      channelUtilization != null ||
      airUtilization != null;
  Map<String, dynamic> toJson() => {
    'radio': radio,
    'node': node,
    'time': time.toIso8601String(),
    'battery': battery,
    'powered': powered,
    'voltage': voltage != null && voltage!.isFinite ? voltage : null,
    'snr': snr != null && snr!.isFinite ? snr : null,
    'rssi': rssi,
    'channel': channelUtilization != null && channelUtilization!.isFinite
        ? channelUtilization
        : null,
    'air': airUtilization != null && airUtilization!.isFinite
        ? airUtilization
        : null,
  };
  factory TelemetrySample.fromJson(Map<String, dynamic> j) => TelemetrySample(
    radio: j['radio'] as int,
    node: j['node'] as int,
    time: DateTime.parse(j['time'] as String),
    battery: j['battery'] as int?,
    powered: j['powered'] as bool?,
    voltage: (j['voltage'] as num?)?.toDouble(),
    snr: (j['snr'] as num?)?.toDouble(),
    rssi: j['rssi'] as int?,
    channelUtilization: (j['channel'] as num?)?.toDouble(),
    airUtilization: (j['air'] as num?)?.toDouble(),
  );
}
