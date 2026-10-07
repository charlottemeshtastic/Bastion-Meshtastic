import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'bastion_chat_message.dart';

class BastionArchiveSnapshot {
  const BastionArchiveSnapshot({
    this.messages = const [],
    this.pending = const [],
  });

  final List<BastionChatMessage> messages;
  final List<PendingTextMessage> pending;
}

/// Small durable archive for COMMS history and the outbound offline queue.
class BastionMessageArchive {
  BastionMessageArchive({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'bastion.comms.archive.v1';
  final SharedPreferencesAsync _preferences;

  Future<BastionArchiveSnapshot> load() async {
    final raw = await _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const BastionArchiveSnapshot();
    try {
      final root = jsonDecode(raw) as Map<String, Object?>;
      final messages = (root['messages'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(BastionChatMessage.fromJson)
          .toList();
      final pending = (root['pending'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(PendingTextMessage.fromJson)
          .toList();
      return BastionArchiveSnapshot(messages: messages, pending: pending);
    } catch (_) {
      return const BastionArchiveSnapshot();
    }
  }

  Future<void> save({
    required List<BastionChatMessage> messages,
    required List<PendingTextMessage> pending,
  }) {
    final encoded = jsonEncode({
      'messages': messages.takeLast(500).map((m) => m.toJson()).toList(),
      'pending': pending.map((m) => m.toJson()).toList(),
    });
    return _preferences.setString(_key, encoded);
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.skip(list.length - count);
  }
}
