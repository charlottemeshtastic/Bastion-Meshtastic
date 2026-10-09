import 'dart:convert';
import 'dart:typed_data';

/// Versioned, local-only backup envelope. Does not upload keys to any server.
abstract final class BastionConfigBackup {
  static const formatVersion = 1;

  static String exportSnapshot({
    required List<Uint8List> config,
    required List<Uint8List> channels,
    required List<Uint8List> modules,
  }) => jsonEncode({
    'format': 'bastion-meshtastic-backup',
    'version': formatVersion,
    'config': config.map(base64Encode).toList(),
    'channels': channels.map(base64Encode).toList(),
    'modules': modules.map(base64Encode).toList(),
  });

  static Map<String, dynamic> parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'bastion-meshtastic-backup' ||
        decoded['version'] != formatVersion) {
      throw const FormatException('Unsupported Bastion backup format');
    }
    for (final key in ['config', 'channels', 'modules']) {
      final values = decoded[key];
      if (values is! List || values.any((v) => v is! String)) {
        throw FormatException('Invalid $key backup entries');
      }
      for (final value in values) {
        base64Decode(value as String);
      }
    }
    return decoded;
  }
}
