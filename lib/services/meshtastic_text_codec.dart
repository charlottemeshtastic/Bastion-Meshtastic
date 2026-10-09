import 'dart:convert';
import 'dart:typed_data';

/// Minimal Meshtastic MeshPacket/Data codec for UTF-8 text messaging.
///
/// Field numbers mirror the official Meshtastic protobuf schema. Keeping this
/// small avoids coupling the transport layer to generated protobuf sources.
abstract final class MeshtasticTextCodec {
  static const int textMessagePort = 1;
  static const int broadcastNode = 0xffffffff;

  static MeshtasticTextMessage? decodeMeshPacket(Uint8List bytes) {
    var offset = 0;
    var from = 0;
    var to = 0;
    var channel = 0;
    var packetId = 0;
    int? rxTime;
    double? rxSnr;
    Uint8List? decoded;

    while (offset < bytes.length) {
      final key = _readVarint(bytes, offset);
      offset = key.next;
      final field = key.value >> 3;
      final wire = key.value & 7;
      if (field == 1 && wire == 5) {
        from = _readFixed32(bytes, offset);
        offset += 4;
      } else if (field == 2 && wire == 5) {
        to = _readFixed32(bytes, offset);
        offset += 4;
      } else if (field == 3 && wire == 0) {
        final v = _readVarint(bytes, offset);
        channel = v.value;
        offset = v.next;
      } else if (field == 4 && wire == 2) {
        final v = _readBytes(bytes, offset);
        decoded = v.bytes;
        offset = v.next;
      } else if (field == 6 && wire == 5) {
        packetId = _readFixed32(bytes, offset);
        offset += 4;
      } else if (field == 7 && wire == 5) {
        rxTime = _readFixed32(bytes, offset);
        offset += 4;
      } else if (field == 8 && wire == 5) {
        _require(bytes, offset, 4);
        rxSnr = ByteData.sublistView(bytes, offset, offset + 4)
            .getFloat32(0, Endian.little);
        offset += 4;
      } else {
        offset = _skip(bytes, offset, wire);
      }
    }

    if (decoded == null) return null;
    final data = _decodeData(decoded);
    if (data == null || data.port != textMessagePort) return null;
    return MeshtasticTextMessage(
      packetId: packetId,
      from: from,
      to: to,
      channel: channel,
      text: utf8.decode(data.payload, allowMalformed: true),
      rxTime: rxTime,
      rxSnr: rxSnr,
    );
  }

  /// Parse a routing response correlated with an outgoing direct-message ID.
  /// Routing error 0 means an ACK; nonzero values are delivery failures.
  static ({int requestId, int from, int errorReason})? decodeRoutingAck(
      Uint8List bytes) {
    var offset = 0;
    var from = 0;
    Uint8List? decoded;
    while (offset < bytes.length) {
      final tag = _readVarint(bytes, offset);
      offset = tag.next;
      final field = tag.value >> 3;
      final wire = tag.value & 7;
      if (field == 1 && wire == 5) {
        from = _readFixed32(bytes, offset);
        offset += 4;
      } else if (field == 4 && wire == 2) {
        final value = _readBytes(bytes, offset);
        decoded = value.bytes;
        offset = value.next;
      } else {
        offset = _skip(bytes, offset, wire);
      }
    }
    if (decoded == null) return null;
    offset = 0;
    var port = 0;
    var requestId = 0;
    Uint8List? routing;
    while (offset < decoded.length) {
      final tag = _readVarint(decoded, offset);
      offset = tag.next;
      final field = tag.value >> 3;
      final wire = tag.value & 7;
      if (field == 1 && wire == 0) {
        final value = _readVarint(decoded, offset);
        port = value.value;
        offset = value.next;
      } else if (field == 2 && wire == 2) {
        final value = _readBytes(decoded, offset);
        routing = value.bytes;
        offset = value.next;
      } else if (field == 6 && wire == 0) {
        final value = _readVarint(decoded, offset);
        requestId = value.value;
        offset = value.next;
      } else {
        offset = _skip(decoded, offset, wire);
      }
    }
    if (port != 5 || requestId == 0 || routing == null) return null;
    offset = 0;
    int? errorReason;
    while (offset < routing.length) {
      final tag = _readVarint(routing, offset);
      offset = tag.next;
      if (tag.value >> 3 == 1 && tag.value & 7 == 0) {
        final value = _readVarint(routing, offset);
        errorReason = value.value;
        offset = value.next;
      } else {
        offset = _skip(routing, offset, tag.value & 7);
      }
    }
    if (errorReason == null) return null;
    return (requestId: requestId, from: from, errorReason: errorReason);
  }

  static Uint8List toRadioText({
    required String text,
    required int destination,
    int channel = 0,
    required int packetId,
    bool wantAck = false,
  }) {
    if (packetId <= 0 || packetId > 0xffffffff) {
      throw ArgumentError.value(packetId, 'packetId', 'must be a non-zero uint32');
    }
    if (destination < 0 || destination > 0xffffffff) {
      throw ArgumentError.value(destination, 'destination', 'must be a uint32');
    }
    final payload = utf8.encode(text);
    if (payload.isEmpty) throw ArgumentError.value(text, 'text', 'must not be empty');

    final data = <int>[
      0x08, textMessagePort,
      0x12, ..._varint(payload.length), ...payload,
    ];
    final packet = <int>[
      0x15, ..._fixed32(destination),
      if (channel != 0) 0x18, if (channel != 0) ..._varint(channel),
      0x22, ..._varint(data.length), ...data,
      0x35, ..._fixed32(packetId),
      if (wantAck) 0x50, if (wantAck) 0x01,
    ];
    return Uint8List.fromList([
      0x0a, ..._varint(packet.length), ...packet,
    ]);
  }

  static _DataPayload? _decodeData(Uint8List bytes) {
    var offset = 0;
    var port = 0;
    Uint8List? payload;
    while (offset < bytes.length) {
      final key = _readVarint(bytes, offset);
      offset = key.next;
      final field = key.value >> 3;
      final wire = key.value & 7;
      if (field == 1 && wire == 0) {
        final v = _readVarint(bytes, offset);
        port = v.value;
        offset = v.next;
      } else if (field == 2 && wire == 2) {
        final v = _readBytes(bytes, offset);
        payload = v.bytes;
        offset = v.next;
      } else {
        offset = _skip(bytes, offset, wire);
      }
    }
    return payload == null ? null : _DataPayload(port, payload);
  }

  static List<int> _varint(int value) {
    final out = <int>[];
    var v = value;
    do {
      var b = v & 0x7f;
      v >>= 7;
      if (v != 0) b |= 0x80;
      out.add(b);
    } while (v != 0);
    return out;
  }

  static List<int> _fixed32(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];

  static int _readFixed32(Uint8List bytes, int offset) {
    _require(bytes, offset, 4);
    return ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.little);
  }

  static _Varint _readVarint(Uint8List bytes, int start) {
    var value = 0, shift = 0, offset = start;
    while (offset < bytes.length && shift < 64) {
      final b = bytes[offset++];
      value |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) return _Varint(value, offset);
      shift += 7;
    }
    throw const FormatException('Invalid protobuf varint.');
  }

  static _Bytes _readBytes(Uint8List bytes, int offset) {
    final len = _readVarint(bytes, offset);
    final end = len.next + len.value;
    if (end > bytes.length) throw const FormatException('Truncated protobuf bytes.');
    return _Bytes(Uint8List.sublistView(bytes, len.next, end), end);
  }

  static int _skip(Uint8List bytes, int offset, int wire) {
    switch (wire) {
      case 0:
        return _readVarint(bytes, offset).next;
      case 1:
        _require(bytes, offset, 8);
        return offset + 8;
      case 2:
        return _readBytes(bytes, offset).next;
      case 5:
        _require(bytes, offset, 4);
        return offset + 4;
      default:
        throw FormatException('Unsupported protobuf wire type $wire.');
    }
  }

  static void _require(Uint8List bytes, int offset, int length) {
    if (offset + length > bytes.length) {
      throw const FormatException('Truncated protobuf field.');
    }
  }
}

class MeshtasticTextMessage {
  const MeshtasticTextMessage({
    required this.packetId,
    required this.from,
    required this.to,
    required this.channel,
    required this.text,
    this.rxTime,
    this.rxSnr,
  });

  final int packetId;
  final int from;
  final int to;
  final int channel;
  final String text;
  final int? rxTime;
  final double? rxSnr;

  bool get isBroadcast => to == MeshtasticTextCodec.broadcastNode;
}

class _DataPayload {
  const _DataPayload(this.port, this.payload);
  final int port;
  final Uint8List payload;
}

class _Varint {
  const _Varint(this.value, this.next);
  final int value;
  final int next;
}

class _Bytes {
  const _Bytes(this.bytes, this.next);
  final Uint8List bytes;
  final int next;
}
