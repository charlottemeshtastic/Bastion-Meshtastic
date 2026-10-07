import 'dart:typed_data';

enum FromRadioPayloadKind {
  packet(2), myInfo(3), nodeInfo(4), config(5), logRecord(6),
  configCompleteId(7), rebooted(8), moduleConfig(9), channel(10),
  queueStatus(11), xmodemPacket(12), metadata(13),
  mqttClientProxyMessage(14), fileInfo(15), clientNotification(16),
  deviceUi(17), unknown(-1);

  const FromRadioPayloadKind(this.fieldNumber);
  final int fieldNumber;

  static FromRadioPayloadKind fromField(int field) {
    for (final value in values) {
      if (value.fieldNumber == field) return value;
    }
    return unknown;
  }
}

class FromRadioEnvelope {
  const FromRadioEnvelope({
    required this.id,
    required this.kind,
    this.payload,
    this.scalarValue,
  });

  final int id;
  final FromRadioPayloadKind kind;
  final Uint8List? payload;
  final int? scalarValue;

  int? get configCompleteId =>
      kind == FromRadioPayloadKind.configCompleteId ? scalarValue : null;
  bool get rebooted =>
      kind == FromRadioPayloadKind.rebooted && scalarValue != 0;
}

/// Minimal PhoneAPI protobuf root-envelope codec.
///
/// Nested Meshtastic messages remain opaque here and are decoded by their
/// dedicated model layers. This keeps transport/session code schema-agnostic.
abstract final class MeshtasticPhoneApiCodec {
  static Uint8List wantConfig(int id) {
    _checkUint32(id, 'id');
    return Uint8List.fromList([0x18, ..._encodeVarint(id)]);
  }

  static Uint8List heartbeat(int nonce) {
    _checkUint32(nonce, 'nonce');
    final inner = <int>[0x08, ..._encodeVarint(nonce)];
    return Uint8List.fromList([0x3a, ..._encodeVarint(inner.length), ...inner]);
  }

  static Uint8List disconnect() => Uint8List.fromList([0x20, 0x01]);

  static FromRadioEnvelope decodeFromRadio(Uint8List bytes) {
    var offset = 0;
    var id = 0;
    var kind = FromRadioPayloadKind.unknown;
    Uint8List? payload;
    int? scalar;

    while (offset < bytes.length) {
      final key = _readVarint(bytes, offset);
      offset = key.next;
      final field = key.value >> 3;
      final wireType = key.value & 0x07;

      if (field == 1 && wireType == 0) {
        final value = _readVarint(bytes, offset);
        id = value.value;
        offset = value.next;
        continue;
      }

      if (field >= 2 && field <= 17) {
        kind = FromRadioPayloadKind.fromField(field);
        if (wireType == 0) {
          final value = _readVarint(bytes, offset);
          scalar = value.value;
          offset = value.next;
          continue;
        }
        if (wireType == 2) {
          final length = _readVarint(bytes, offset);
          offset = length.next;
          final end = offset + length.value;
          if (end > bytes.length) {
            throw const FormatException('Truncated FromRadio payload.');
          }
          payload = Uint8List.sublistView(bytes, offset, end);
          offset = end;
          continue;
        }
      }

      offset = _skipField(bytes, offset, wireType);
    }

    return FromRadioEnvelope(
      id: id,
      kind: kind,
      payload: payload,
      scalarValue: scalar,
    );
  }

  static void _checkUint32(int value, String name) {
    if (value <= 0 || value > 0xffffffff) {
      throw ArgumentError.value(value, name, 'must be a non-zero uint32');
    }
  }

  static List<int> _encodeVarint(int value) {
    final out = <int>[];
    var remaining = value;
    do {
      var byte = remaining & 0x7f;
      remaining >>= 7;
      if (remaining != 0) byte |= 0x80;
      out.add(byte);
    } while (remaining != 0);
    return out;
  }

  static _Varint _readVarint(Uint8List bytes, int start) {
    var value = 0;
    var shift = 0;
    var offset = start;
    while (offset < bytes.length && shift < 64) {
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return _Varint(value, offset);
      shift += 7;
    }
    throw const FormatException('Invalid protobuf varint.');
  }

  static int _skipField(Uint8List bytes, int offset, int wireType) {
    switch (wireType) {
      case 0:
        return _readVarint(bytes, offset).next;
      case 1:
        if (offset + 8 > bytes.length) {
          throw const FormatException('Truncated fixed64 field.');
        }
        return offset + 8;
      case 2:
        final length = _readVarint(bytes, offset);
        final end = length.next + length.value;
        if (end > bytes.length) {
          throw const FormatException('Truncated length-delimited field.');
        }
        return end;
      case 5:
        if (offset + 4 > bytes.length) {
          throw const FormatException('Truncated fixed32 field.');
        }
        return offset + 4;
      default:
        throw FormatException('Unsupported protobuf wire type $wireType.');
    }
  }
}

class _Varint {
  const _Varint(this.value, this.next);
  final int value;
  final int next;
}
