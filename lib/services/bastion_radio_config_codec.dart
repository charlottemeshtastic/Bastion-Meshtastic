import 'dart:convert';
import 'dart:typed_data';

/// Read-only views of the Meshtastic Config and Channel protobuf payloads.
/// Unknown fields are skipped, and no private channel PSKs are exposed.
abstract final class BastionRadioConfigCodec {
  static Map<int, Object> fields(Uint8List data) {
    final result = <int, Object>{};
    var offset = 0;
    int varint() {
      var value = 0;
      var shift = 0;
      while (offset < data.length && shift < 70) {
        final b = data[offset++];
        value |= (b & 127) << shift;
        if (b < 128) return value;
        shift += 7;
      }
      throw const FormatException('Invalid protobuf varint');
    }
    while (offset < data.length) {
      final key = varint();
      final number = key >> 3;
      if (number == 0) throw const FormatException('Invalid protobuf tag');
      switch (key & 7) {
        case 0:
          result[number] = varint();
        case 2:
          final length = varint();
          if (length > data.length - offset) {
            throw const FormatException('Truncated protobuf payload');
          }
          result[number] = Uint8List.sublistView(data, offset, offset + length);
          offset += length;
        case 1:
          if (offset + 8 > data.length) throw const FormatException('Truncated fixed64');
          offset += 8;
        case 5:
          if (offset + 4 > data.length) throw const FormatException('Truncated fixed32');
          offset += 4;
        default:
          throw FormatException('Unsupported protobuf wire type ${key & 7}');
      }
    }
    return result;
  }

  static String? loraSummary(Uint8List config) {
    final lora = fields(config)[6];
    if (lora is! Uint8List) return null;
    final values = fields(lora);
    return 'Region: ${values[7] ?? 'not reported'} • '
        'Preset: ${values[2] ?? 'not reported'} • '
        'Hop limit: ${values[8] ?? 'not reported'}';
  }

  /// Decode non-secret channel metadata for UI use.
  /// The raw PSK is intentionally never returned.
  static ({int index, int role, String name}) channelMetadata(Uint8List channel) {
    final values = fields(channel);
    final index = values[1];
    final role = values[3];
    final settings = values[2];
    if (index is! int || index < 0 || index > 7 ||
        role is! int || role < 0 || role > 2 ||
        settings is! Uint8List) {
      throw const FormatException('Invalid channel metadata');
    }
    final details = fields(settings);
    final nameBytes = details[3];
    if (nameBytes != null && nameBytes is! Uint8List) {
      throw const FormatException('Invalid channel name');
    }
    return (
      index: index,
      role: role,
      name: nameBytes is Uint8List ? utf8.decode(nameBytes) : '',
    );
  }

  static String channelSummary(Uint8List channel) {
    final values = fields(channel);
    final settings = values[2];
    final details = settings is Uint8List ? fields(settings) : <int, Object>{};
    final name = details[3] is Uint8List
        ? utf8.decode(details[3] as Uint8List, allowMalformed: true)
        : '';
    final role = switch (values[3]) { 1 => 'Primary', 2 => 'Secondary', _ => 'Disabled' };
    return 'Channel ${values[1] ?? '?'} • $role • ${name.isEmpty ? '(default)' : name}';
  }
}
