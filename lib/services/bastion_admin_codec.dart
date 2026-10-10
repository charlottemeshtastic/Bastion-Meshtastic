import 'dart:typed_data';

/// Encodes Meshtastic AdminMessage setters, not raw ToRadio configuration fields.
///
/// These payloads must be wrapped in a MeshPacket with ADMIN_APP (port 6),
/// addressed to the local node, and sent only after authentication and user
/// confirmation. Never send the returned bytes directly to the BLE transport.
abstract final class BastionAdminCodec {
  static Uint8List setOwner(Uint8List user) => _message(32, user);
  static Uint8List setChannel(Uint8List channel) => _message(33, channel);
  static Uint8List setConfig(Uint8List config) => _message(34, config);
  static Uint8List setModuleConfig(Uint8List module) => _message(35, module);

  /// Current firmware can require an ephemeral session passkey (field 101).
  /// A missing passkey must be handled by the admin session, not guessed here.
  static Uint8List withSessionPasskey(Uint8List admin, Uint8List passkey) {
    if (passkey.isEmpty) throw ArgumentError.value(passkey, 'passkey', 'cannot be empty');
    return Uint8List.fromList([...admin, ..._tag(101, passkey)]);
  }

  static Uint8List _message(int field, Uint8List payload) {
    if (payload.isEmpty) throw ArgumentError.value(payload, 'payload', 'cannot be empty');
    return Uint8List.fromList(_tag(field, payload));
  }

  static List<int> _tag(int field, Uint8List payload) =>
      [..._varint((field << 3) | 2), ..._varint(payload.length), ...payload];

  static List<int> _varint(int value) {
    final bytes = <int>[];
    do {
      var byte = value & 127;
      value >>= 7;
      if (value != 0) byte |= 128;
      bytes.add(byte);
    } while (value != 0);
    return bytes;
  }
}
