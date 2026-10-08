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
      : _preferences = preferences;

  static const _key = 'bastion.comms.archive.v1';
  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();

  Future<BastionArchiveSnapshot> load() async {
    try {
      final raw = await _store.getString(_key);
      if (raw == null || raw.isEmpty) return const BastionArchiveSnapshot();
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
  }) async {
    try {
      final encoded = jsonEncode({
        'messages': messages.takeLast(500).map((m) => m.toJson()).toList(),
        'pending': pending.map((m) => m.toJson()).toList(),
      });
      await _store.setString(_key, encoded);
    } catch (_) {
      // Persistence must never prevent COMMS or the app shell from operating.
    }
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.skip(list.length - count);
  }
}
