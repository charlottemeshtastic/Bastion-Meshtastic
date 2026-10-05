import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/chat_message.dart';

/// Local bounded history. Event updates serialize to preserve final send status.
class ChatHistory extends ChangeNotifier {
  static const storageKey = 'bastion.chat.history.v1';
  final Map<String, ChatMessage> _messages = {};
  List<ChatMessage> get messages {
    final values = _messages.values.toList()..sort((a, b) => a.time.compareTo(b.time));
    return List.unmodifiable(values);
  }
  bool loading = true;
  String? error;
  bool _disposed = false;
  bool _loaded = false;
  Future<void> _writes = Future<void>.value();
  Future<void> get saved => _writes;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(storageKey);
      if (encoded != null) {
        for (final entry in jsonDecode(encoded) as List) {
          var message = ChatMessage.fromJson(Map<String, dynamic>.from(entry as Map));
          if (message.outgoing && (message.state == MessageState.writing ||
              message.state == MessageState.written)) {
            message = message.withState(MessageState.unknown, 'App restarted before confirmation.');
          }
          // A live event received during loading always wins over disk state.
          _messages.putIfAbsent(message.key, () => message);
        }
      }
      _loaded = true;
      _trim();
      _persist();
    } catch (_) {
      error = 'Chat history could not be loaded. Sending is disabled to protect saved history.';
    } finally {
      loading = false;
      _notify();
    }
  }

  void upsert(ChatMessage message) {
    if (_disposed) {
      return;
    }
    _messages[message.key] = message;
    _trim();
    if (_loaded) {
      _persist();
    }
    _notify();
  }

  void _trim() {
    final ordered = messages;
    if (ordered.length > 1000) {
      for (final message in ordered.take(ordered.length - 1000)) {
        _messages.remove(message.key);
      }
    }
  }

  void _persist() {
    final encoded = jsonEncode(messages.map((m) => m.toJson()).toList());
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(storageKey, encoded)) {
          throw StateError('Save failed');
        }
      } catch (_) {
        error = 'Messages are visible, but chat history could not be saved.';
        _notify();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
