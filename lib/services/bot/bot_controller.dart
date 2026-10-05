import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/chat_message.dart';
import '../meshtastic/radio_session.dart';
import 'bot_engine.dart';

class BotActivity {
  BotActivity({
    required this.id,
    required this.time,
    required this.radio,
    required this.peer,
    required this.channel,
    required this.trigger,
    required this.outcome,
    this.outgoingKey,
    this.attempted = false,
  });
  final String id;
  final DateTime time;
  final int radio;
  final int peer;
  final int channel;
  final String trigger;
  final bool attempted;
  String outcome;
  String? outgoingKey;
  Map<String, Object?> toJson() => {
    'id': id,
    'time': time.toIso8601String(),
    'radio': radio,
    'peer': peer,
    'channel': channel,
    'trigger': trigger,
    'outcome': outcome,
    'outgoingKey': outgoingKey,
    'attempted': attempted,
  };
  factory BotActivity.fromJson(Map<String, dynamic> j) => BotActivity(
    id: j['id'] as String,
    time: DateTime.parse(j['time'] as String),
    radio: j['radio'] as int,
    peer: j['peer'] as int,
    channel: j['channel'] as int,
    trigger: j['trigger'] as String,
    outcome: j['outcome'] as String,
    outgoingKey: j['outgoingKey'] as String?,
    attempted: j['attempted'] as bool,
  );
}

class BotController extends ChangeNotifier {
  BotController(this.session, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _subscription = session.messages.listen(_onMessage);
    session.addListener(_sessionChanged);
  }
  static const storageKey = 'bastion.bot.v1';
  final RadioSession session;
  final DateTime Function() _clock;
  final _engine = BotEngine();
  late final StreamSubscription<ChatMessage> _subscription;
  BotSettings settings = const BotSettings();
  bool enabled = false;
  bool loading = true;
  bool saving = false;
  bool loadFailed = false;
  int? armedRadio;
  String? error;
  bool _disposed = false;
  BotActivity? _sending;
  String? _sendingText;
  int? _sendingDestination;
  final List<BotActivity> _activities = [];
  List<BotActivity> get activities => List.unmodifiable(_activities.reversed);
  Future<void> _writes = Future.value();
  Future<void> get saved => _writes;
  Future<void> _sendComplete = Future.value();
  Future<void> get sendComplete => _sendComplete;

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
        final j = jsonDecode(encoded) as Map<String, dynamic>;
        final loadedSettings = BotSettings.fromJson(
          j['settings'] as Map<String, dynamic>,
        );
        if (loadedSettings.validationError != null) {
          throw const FormatException('Invalid bot settings');
        }
        final loaded = (j['activities'] as List)
            .map(
              (v) => BotActivity.fromJson(Map<String, dynamic>.from(v as Map)),
            )
            .toList();
        settings = loadedSettings;
        for (final activity in loaded) {
          if (activity.outcome == 'Sending to radio…' ||
              activity.outcome ==
                  'Written to radio · awaiting acknowledgement') {
            activity.outcome = 'Delivery unconfirmed · app restarted';
          }
        }
        _activities.addAll(
          loaded.skip(loaded.length > 100 ? loaded.length - 100 : 0),
        );
        final attempts = j['attempts'] as List;
        if (attempts.length > 6) {
          throw const FormatException('Invalid bot limits');
        }
        for (final raw in attempts) {
          final a = Map<String, dynamic>.from(raw as Map);
          _engine.restoreAttempt(
            a['radio'] as int,
            a['peer'] as int,
            DateTime.parse(a['time'] as String),
          );
        }
      }
      // Runtime enablement is never restored; explicit activation is required.
    } catch (_) {
      loadFailed = true;
      error =
          'Bot settings could not be loaded. Bot is disabled to protect saved data.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> saveSettings(BotSettings value) async {
    if (_disposed || loading || saving || loadFailed) {
      return false;
    }
    if (value.validationError != null) {
      error = value.validationError;
      _notify();
      return false;
    }
    // Editing always disarms; the user can review then explicitly enable.
    enabled = false;
    armedRadio = null;
    settings = BotSettings.fromJson(value.toJson());
    saving = true;
    error = null;
    _persist();
    _notify();
    await saved;
    saving = false;
    _notify();
    return error == null;
  }

  void setEnabled(bool value) {
    if (_disposed || loading || saving || loadFailed) {
      return;
    }
    if (value &&
        (session.status != RadioStatus.ready || session.localNode == null)) {
      error = 'Connect a radio before enabling Bot Mode.';
      _notify();
      return;
    }
    if (value && settings.validationError != null) {
      error = settings.validationError;
      _notify();
      return;
    }
    enabled = value;
    armedRadio = value ? session.localNode : null;
    error = null;
    _notify();
  }

  void pause() {
    if (enabled) {
      enabled = false;
      armedRadio = null;
      _notify();
    }
  }

  void _sessionChanged() {
    if (session.status != RadioStatus.ready ||
        session.localNode != armedRadio) {
      pause();
    }
  }

  void _onMessage(ChatMessage message) {
    if (_disposed) {
      return;
    }
    if (message.outgoing) {
      final pending = _sending;
      if (pending != null &&
          pending.outgoingKey == null &&
          message.radio == pending.radio &&
          message.channel == pending.channel &&
          message.to == _sendingDestination &&
          message.text == _sendingText) {
        pending.outgoingKey = message.key;
      }
      for (final activity in _activities) {
        if (activity.outgoingKey == message.key) {
          activity.outcome = message.statusLabel;
          _persist();
          _notify();
          break;
        }
      }
      return;
    }
    final decision = _engine.evaluate(
      message,
      settings,
      now: _clock(),
      enabled: enabled && !loading && !saving && !loadFailed,
      armedRadio: armedRadio,
      ready: session.status == RadioStatus.ready,
      channelEnabled:
          session.channels[message.channel] != null &&
          session.channels[message.channel]!.role.name != 'DISABLED',
      nodeCount: session.nodes.length,
    );
    if (!enabled || decision.reason == 'Duplicate packet') {
      return;
    }
    if (_sending != null && decision.replies) {
      // Never queue a reply for later, or retry an interrupted send.
      _record(
        message,
        'Busy · reply skipped',
        attempted: true,
        trigger: decision.command ?? 'Auto-reply',
      );
      return;
    }
    final activity = _record(
      message,
      decision.replies ? 'Sending to radio…' : 'Skipped · ${decision.reason}',
      attempted: decision.replies,
      trigger: decision.command ?? 'Message',
    );
    if (!decision.replies) {
      return;
    }
    _sending = activity;
    _sendingText = decision.text;
    _sendingDestination = decision.destination;
    _sendComplete = _send(message, decision, activity);
  }

  Future<void> _send(
    ChatMessage incoming,
    BotDecision decision,
    BotActivity activity,
  ) async {
    try {
      // All gates are synchronous before sendText; there is no waiting queue.
      await session.sendText(
        decision.text!,
        channel: incoming.channel,
        destination: decision.destination!,
      );
    } catch (_) {
      if (activity.outgoingKey == null) {
        activity.outcome = 'Send failed before radio write · no retry';
      }
    } finally {
      if (!_disposed) {
        _sending = null;
        _sendingText = null;
        _sendingDestination = null;
        _persist();
        _notify();
      }
    }
  }

  BotActivity _record(
    ChatMessage m,
    String outcome, {
    required bool attempted,
    required String trigger,
  }) {
    final activity = BotActivity(
      id: m.key,
      time: _clock(),
      radio: m.radio,
      peer: m.from,
      channel: m.channel,
      trigger: trigger,
      outcome: outcome,
      attempted: attempted,
    );
    _activities.add(activity);
    if (_activities.length > 100) {
      _activities.removeAt(0);
    }
    _persist();
    _notify();
    return activity;
  }

  Future<void> clearActivity() async {
    if (loading || saving || loadFailed) {
      return;
    }
    _activities.clear();
    _persist();
    _notify();
    await saved;
  }

  void _persist() {
    if (loading || loadFailed || _disposed) {
      return;
    }
    final encoded = jsonEncode({
      'settings': settings.toJson(),
      'activities': _activities.map((a) => a.toJson()).toList(),
      'attempts': _engine.attemptsJson,
    });
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(storageKey, encoded)) {
          throw StateError('Save failed');
        }
      } catch (_) {
        error = 'Bot data could not be saved. Bot has been turned off.';
        pause();
        _notify();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    enabled = false;
    session.removeListener(_sessionChanged);
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
