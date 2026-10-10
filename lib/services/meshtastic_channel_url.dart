import 'dart:convert';

import 'package:protobuf/protobuf.dart';

import '../generated/meshtastic/apponly.pb.dart';

/// Encodes and decodes Meshtastic channel share links.
///
/// The link is `https://meshtastic.org/e/#` followed by the unpadded
/// base64url encoding of a [ChannelSet]: the enabled channels in slot order
/// (primary first) plus the LoRa config. Anyone with the link can read the
/// channels, because it contains their encryption keys.
abstract final class MeshtasticChannelUrl {
  static const prefix = 'https://meshtastic.org/e/#';

  static String encode(ChannelSet channels) =>
      prefix + base64Url.encode(channels.writeToBuffer()).replaceAll('=', '');

  /// Accepts the official link (including the `?add=true` variant used to add
  /// channels instead of replacing them), or the bare encoded fragment.
  static ChannelSet decode(String link) {
    final text = link.trim();
    final hash = text.indexOf('#');
    final fragment = hash >= 0 ? text.substring(hash + 1) : text;
    if (fragment.isEmpty) throw const FormatException('Link has no channel data.');
    final normalized = fragment.replaceAll('+', '-').replaceAll('/', '_');
    final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
    final List<int> bytes;
    try {
      bytes = base64Url.decode(padded);
    } on FormatException {
      throw const FormatException('Link is not a valid Meshtastic channel link.');
    }
    final ChannelSet set;
    try {
      set = ChannelSet.fromBuffer(bytes);
    } on InvalidProtocolBufferException {
      throw const FormatException('Link is not a valid Meshtastic channel link.');
    }
    if (set.settings.isEmpty) throw const FormatException('Link contains no channels.');
    if (set.settings.length > 8) throw const FormatException('Link has more than 8 channels.');
    return set;
  }

  /// Whether the link asks to add channels rather than replace them.
  static bool isAddLink(String link) => link.contains('add=true');
}
