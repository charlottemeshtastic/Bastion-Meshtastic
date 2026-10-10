import 'dart:convert';
import 'dart:typed_data';

import 'bastion_admin_codec.dart';
import 'bastion_node_identity_validation.dart';

/// Builds a Meshtastic User owner update; does not transmit it.
abstract final class BastionOwnerCodec {
  static Uint8List encodeUser({
    required String longName,
    required String shortName,
  }) {
    final longError = BastionNodeIdentityValidation.longNameError(longName);
    if (longError != null) throw ArgumentError.value(longName, 'longName', longError);
    final shortError = BastionNodeIdentityValidation.shortNameError(shortName);
    if (shortError != null) throw ArgumentError.value(shortName, 'shortName', shortError);
    final longBytes = utf8.encode(longName.trim());
    final shortBytes = utf8.encode(shortName.trim());
    if (longBytes.length > 39 || shortBytes.length > 4) {
      throw ArgumentError('Node names exceed Meshtastic UTF-8 byte limits.');
    }
    return Uint8List.fromList([
      0x12, longBytes.length, ...longBytes, // User.long_name, field 2
      0x1a, shortBytes.length, ...shortBytes, // User.short_name, field 3
    ]);
  }

  static Uint8List encodeAdminSetOwner({
    required String longName,
    required String shortName,
  }) => BastionAdminCodec.setOwner(
        encodeUser(longName: longName, shortName: shortName),
      );
}
