import 'dart:typed_data';

/// Minimal decoder for received Meshtastic device telemetry packets.
///
/// MeshPacket.decoded is field 4, Data.portnum is field 1 and Data.payload
/// is field 2. TELEMETRY_APP is port 67. Telemetry.device_metrics is field 2.
/// This decoder does not send requests or assume every node supports metrics.
class BastionDeviceTelemetry {
  const BastionDeviceTelemetry({
    required this.from,
    this.batteryLevel,
    this.voltage,
    this.channelUtilization,
    this.airUtilTx,
  });

  final int from;
  final int? batteryLevel;
  final double? voltage;
  final double? channelUtilization;
  final double? airUtilTx;
}

abstract final class BastionTelemetryCodec {
  static const telemetryPort = 67;

  static BastionDeviceTelemetry? decodeMeshPacket(Uint8List packet) {
    final mesh = _Fields(packet);
    final from = mesh.fixed32(1);
    final decoded = mesh.bytes(4);
    if (from == null || decoded == null) return null;
    final data = _Fields(decoded);
    if (data.varint(1) != telemetryPort) return null;
    final payload = data.bytes(2);
    if (payload == null) return null;
    final telemetry = _Fields(payload);
    final metricsBytes = telemetry.bytes(2);
    if (metricsBytes == null) return null;
    final metrics = _Fields(metricsBytes);
    final battery = metrics.varint(1);
    final voltage = metrics.float32(2);
    final channel = metrics.float32(3);
    final air = metrics.float32(4);
    if (battery == null && voltage == null && channel == null && air == null) {
      return null;
    }
    return BastionDeviceTelemetry(
      from: from,
      batteryLevel: battery,
      voltage: voltage,
      channelUtilization: channel,
      airUtilTx: air,
    );
  }
}

/// Strict protobuf wire reader: rejects malformed lengths and unknown wire types.
class _Fields {
  _Fields(this.bytes);
  final Uint8List bytes;

  int? varint(int field) => _read(field, 0) as int?;
  int? fixed32(int field) => _read(field, 5) as int?;
  Uint8List? bytes(int field) => _read(field, 2) as Uint8List?;
  double? float32(int field) {
    final value = _read(field, 5);
    if (value == null) return null;
    final data = ByteData(4)..setUint32(0, value as int, Endian.little);
    final result = data.getFloat32(0, Endian.little);
    return result.isFinite ? result : null;
  }

  Object? _read(int wanted, int wantedWire) {
    var offset = 0;
    Object? found;
    while (offset < bytes.length) {
      final key = _varint(offset);
      offset = key.$2;
      final field = key.$1 >> 3;
      final wire = key.$1 & 7;
      if (field == 0) throw const FormatException('Invalid protobuf field zero');
      Object value;
      switch (wire) {
        case 0:
          final v = _varint(offset);
          value = v.$1;
          offset = v.$2;
        case 1:
          _require(offset, 8);
          value = 0;
          offset += 8;
        case 2:
          final length = _varint(offset);
          offset = length.$2;
          _require(offset, length.$1);
          value = Uint8List.sublistView(bytes, offset, offset + length.$1);
          offset += length.$1;
        case 5:
          _require(offset, 4);
          value = ByteData.sublistView(bytes, offset, offset + 4)
              .getUint32(0, Endian.little);
          offset += 4;
        default:
          throw FormatException('Unsupported protobuf wire type $wire');
      }
      if (field == wanted && wire == wantedWire) found = value;
    }
    return found;
  }

  (int, int) _varint(int start) {
    var value = 0;
    var shift = 0;
    var offset = start;
    while (offset < bytes.length && shift < 64) {
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return (value, offset);
      shift += 7;
    }
    throw const FormatException('Invalid protobuf varint');
  }

  void _require(int offset, int length) {
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('Truncated protobuf field');
    }
  }
}
