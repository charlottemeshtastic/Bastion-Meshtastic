import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/mesh_node.dart';
import '../../models/telemetry_sample.dart';
import 'automation_engine.dart';

class AutomationController extends ChangeNotifier {
  static const storageKey = 'bastion.automation.rules.v1';
  static const _historyKey = 'bastion.automation.alerts.v1';
  final _engine = AutomationEngine();
  int? _radioId;
  int? get radioId => _radioId;
  Future<void> get historySaved => _historyWrite;
  List<AutomationRule> _rules = [];
  final _alerts = <AutomationAlert>[];
  final _liveAlerts = StreamController<AutomationAlert>.broadcast(sync: true);
  Stream<AutomationAlert> get liveAlerts => _liveAlerts.stream;
  List<AutomationRule> get rules => List.unmodifiable(_rules);
  List<AutomationAlert> get alerts => List.unmodifiable(_alerts);
  bool loading = true;
  bool saving = false;
  bool loadFailed = false;
  String? error;
  bool _disposed = false;
  Future<void> _historyWrite = Future<void>.value();

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      _rules = saved == null
          ? []
          : (jsonDecode(saved) as List)
                .map(
                  (item) => AutomationRule.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList();
      final history = prefs.getString(_historyKey);
      if (history != null) {
        _alerts.addAll(
          (jsonDecode(history) as List).map(
            (item) => AutomationAlert(
              item['ruleId'] as String,
              item['nodeId'] as String,
              item['message'] as String,
              DateTime.parse(item['time'] as String),
              radioId: item['radioId'] as int?,
            ),
          ),
        );
      }
    } catch (_) {
      loadFailed = true;
      error = 'Could not load saved automations. Restart before editing rules.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> saveRules(List<AutomationRule> rules) async {
    if (saving || loading || loadFailed || _disposed) {
      return;
    }
    saving = true;
    error = null;
    _notify();
    try {
      if (rules.length > 50 ||
          rules.map((r) => r.id).toSet().length != rules.length) {
        throw ArgumentError(
          'Use at most 50 rules, each with a unique identity.',
        );
      }
      for (final rule in rules) {
        if (rule.validationError != null) {
          throw ArgumentError(rule.validationError);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        storageKey,
        jsonEncode(rules.map((r) => r.toJson()).toList()),
      )) {
        throw StateError('Save failed');
      }
      for (final old in _rules) {
        final updated = rules.where((r) => r.id == old.id).firstOrNull;
        if (updated == null ||
            jsonEncode(updated.toJson()) != jsonEncode(old.toJson())) {
          _engine.forgetRule(old.id);
        }
      }
      _rules = List.of(rules);
    } on ArgumentError catch (e) {
      error = e.message.toString();
    } catch (_) {
      error = 'Rules could not be saved. Please try again.';
    } finally {
      saving = false;
      _notify();
    }
  }

  NodeObservation? _observation(MeshNode node) => node.lastHeard == null
      ? null
      : NodeObservation(
          id: node.id,
          lastHeard: node.lastHeard!,
          battery: node.powered ? 100 : node.battery?.toDouble(),
        );

  /// Seed the radio database silently. Downloaded history is not a new-node event.
  void seed(Iterable<MeshNode> nodes, {int? radioId}) {
    _radioId = radioId;
    _engine.reset();
    for (final node in nodes) {
      final observation = _observation(node);
      // Keep identities even when the radio has no trustworthy last-heard time.
      _engine.seed(
        observation ??
            NodeObservation(
              id: node.id,
              lastHeard: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            ),
      );
    }
  }

  List<AutomationRule> get _eligibleRules =>
      _rules.where((r) => r.radioId == null || r.radioId == _radioId).toList();

  void observe(MeshNode node, {bool batteryFresh = true}) {
    if (loading || loadFailed) {
      return;
    }
    final observation = batteryFresh
        ? _observation(node)
        : (node.lastHeard == null
              ? null
              : NodeObservation(id: node.id, lastHeard: node.lastHeard!));
    if (observation != null) {
      _record(_engine.observe(observation, _eligibleRules, DateTime.now()));
    }
  }

  void observeTelemetry(TelemetrySample sample) {
    if (loading ||
        loadFailed ||
        sample.radio != _radioId ||
        sample.battery == null && sample.powered != true) {
      return;
    }
    final id = '!${sample.node.toRadixString(16).padLeft(8, '0')}';
    _record(
      _engine.observeBattery(
        NodeObservation(
          id: id,
          lastHeard: sample.time,
          battery: sample.powered == true ? 100 : sample.battery?.toDouble(),
        ),
        _eligibleRules,
        DateTime.now(),
      ),
    );
  }

  void tick(DateTime now, {required DateTime? readySince}) {
    if (loading || loadFailed || readySince == null) {
      return;
    }
    // Only infer silence after continuously monitoring for the rule's duration.
    final eligible = _eligibleRules
        .where(
          (r) =>
              r.trigger != RuleTrigger.nodeSilent ||
              now.difference(readySince).inSeconds >= r.threshold * 3600,
        )
        .toList();
    _record(_engine.tick(eligible, now, monitoringConnected: true));
  }

  void _record(List<AutomationAlert> events) {
    if (events.isEmpty || _disposed) {
      return;
    }
    _alerts.insertAll(
      0,
      events.reversed.map(
        (a) => AutomationAlert(
          a.ruleId,
          a.nodeId,
          a.message,
          a.time,
          radioId: _radioId,
        ),
      ),
    );
    if (_alerts.length > 200) {
      _alerts.removeRange(200, _alerts.length);
    }
    _persistHistory();
    for (final event in events) {
      _liveAlerts.add(
        AutomationAlert(
          event.ruleId,
          event.nodeId,
          event.message,
          event.time,
          radioId: _radioId,
        ),
      );
    }
    _notify();
  }

  Future<void> clearHistory() async {
    if (loading || loadFailed || _disposed) {
      return;
    }
    _alerts.clear();
    _persistHistory();
    _notify();
    await historySaved;
  }

  void _persistHistory() {
    final encoded = jsonEncode(
      _alerts
          .map(
            (a) => {
              'ruleId': a.ruleId,
              'nodeId': a.nodeId,
              'message': a.message,
              'time': a.time.toIso8601String(),
              'radioId': a.radioId,
            },
          )
          .toList(),
    );
    _historyWrite = _historyWrite.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_historyKey, encoded)) {
          throw StateError('Save failed');
        }
      } catch (_) {
        error = 'Alert history could not be saved.';
        _notify();
      }
    });
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_liveAlerts.close());
    super.dispose();
  }
}
