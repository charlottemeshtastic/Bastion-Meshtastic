import 'dart:typed_data';

/// Wraps an AdminMessage in a local MeshPacket and ToRadio envelope.
///
/// This only encodes packets. Callers must establish an authorized admin
/// session, track acknowledgements, and verify the radio's readback.
abstract final class BastionAdminPacketCodec {
  static const int adminPort = 6;

  static Uint8List toRadio({
    required Uint8List adminMessage,
    required int localNode,
    required int packetId,
    int channel = 0,
  }) {
    if (adminMessage.isEmpty) {
      throw ArgumentError.value(adminMessage, 'adminMessage', 'cannot be empty');
    }
    if (localNode <= 0 || localNode > 0xffffffff) {
      throw RangeError.range(localNode, 1, 0xffffffff, 'localNode');
    }
    if (packetId <= 0 || packetId > 0xffffffff) {
      throw RangeError.range(packetId, 1, 0xffffffff, 'packetId');
    }
    if (channel < 0 || channel > 255) {
      throw RangeError.range(channel, 0, 255, 'channel');
    }
    final data = <int>[
      0x08, adminPort,
      0x12, ..._varint(adminMessage.length), ...adminMessage,
    ];
    final packet = <int>[
      0x15, ..._fixed32(localNode),
      if (channel != 0) 0x18, if (channel != 0) ..._varint(channel),
      0x22, ..._varint(data.length), ...data,
      0x35, ..._fixed32(packetId),
      0x50, 0x01, // want_ack
    ];
    return Uint8List.fromList([
      0x0a, ..._varint(packet.length), ...packet,
    ]);
  }

  static List<int> _fixed32(int value) => [
    value & 255, (value >> 8) & 255, (value >> 16) & 255,
    (value >> 24) & 255,
  ];

  static List<int> _varint(int value) {
    final out = <int>[];
    do {
      var byte = value & 127;
      value >>= 7;
      if (value != 0) byte |= 128;
      out.add(byte);
    } while (value != 0);
    return out;
  }
}
