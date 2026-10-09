import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_telemetry_codec.dart';

void main() {
  test('decodes device telemetry battery level', () {
    // MeshPacket.from=0x12345678, decoded Data(portnum=67,
    // payload=Telemetry(device_metrics(battery_level=87))).
    final bytes = Uint8List.fromList([
      0x0d, 0x78, 0x56, 0x34, 0x12,
      0x22, 0x08, 0x08, 0x43, 0x12, 0x04, 0x12, 0x02, 0x08, 0x57,
    ]);
    final result = BastionTelemetryCodec.decodeMeshPacket(bytes);
    expect(result?.from, 0x12345678);
    expect(result?.batteryLevel, 87);
    expect(result?.voltage, isNull);
  });

  test('ignores non-telemetry packets', () {
    final bytes = Uint8List.fromList([
      0x0d, 0x78, 0x56, 0x34, 0x12,
      0x22, 0x04, 0x08, 0x01, 0x12, 0x00,
    ]);
    expect(BastionTelemetryCodec.decodeMeshPacket(bytes), isNull);
  });

  test('rejects truncated nested protobuf', () {
    final bytes = Uint8List.fromList([
      0x0d, 0x78, 0x56, 0x34, 0x12, 0x22, 0x05, 0x08, 0x43,
    ]);
    expect(() => BastionTelemetryCodec.decodeMeshPacket(bytes),
        throwsFormatException);
  });

  test('ignores telemetry without device metrics', () {
    final bytes = Uint8List.fromList([
      0x0d, 0x78, 0x56, 0x34, 0x12,
      0x22, 0x04, 0x08, 0x43, 0x12, 0x00,
    ]);
    expect(BastionTelemetryCodec.decodeMeshPacket(bytes), isNull);
  });

  test('ignores telemetry without sender identity', () {
    final bytes = Uint8List.fromList([
      0x22, 0x08, 0x08, 0x43,
      0x12, 0x04, 0x12, 0x02, 0x08, 0x57,
    ]);
    expect(BastionTelemetryCodec.decodeMeshPacket(bytes), isNull);
  });
}
