import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/mesh_node.dart';
import 'automation_engine.dart';

class AutomationController extends ChangeNotifier {
  static const storageKey = 'bastion.automation.rules.v1';
  static const _historyKey = 'bastion.automation.alerts.v1';
  final _engine = AutomationEngine();
  List<AutomationRule> _rules = [];
  final _alerts = <AutomationAlert>[];
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
      _rules = saved == null ? [] : (jsonDecode(saved) as List).map((item) =>
        AutomationRule.fromJson(Map<String, dynamic>.from(item as Map))).toList();
      final history = prefs.getString(_historyKey);
      if (history != null) {
        _alerts.addAll((jsonDecode(history) as List).map((item) =>
          AutomationAlert(item['ruleId'] as String, item['nodeId'] as String,
            item['message'] as String, DateTime.parse(item['time'] as String))));
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
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(storageKey, jsonEncode(rules.map((r) => r.toJson()).toList()))) {
        throw StateError('Save failed');
      }
      _rules = List.of(rules);
    } catch (_) {
      error = 'Rules could not be saved. Please try again.';
    } finally {
      saving = false;
      _notify();
    }
  }

  NodeObservation? _observation(MeshNode node) => node.lastHeard == null ? null :
    NodeObservation(id: node.id, lastHeard: node.lastHeard!,
      battery: node.powered ? 100 : node.battery?.toDouble());

  /// Seed the radio database silently. Downloaded history is not a new-node event.
  void seed(Iterable<MeshNode> nodes) {
    for (final node in nodes) {
      final observation = _observation(node);
      // Keep identities even when the radio has no trustworthy last-heard time.
      _engine.seed(observation ?? NodeObservation(id: node.id,
        lastHeard: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)));
    }
  }

  void observe(MeshNode node) {
    if (loading || loadFailed) {
      return;
    }
    final observation = _observation(node);
    if (observation != null) {
      _record(_engine.observe(observation, _rules, DateTime.now()));
    }
  }

  void tick(DateTime now, {required DateTime? readySince}) {
    if (loading || loadFailed || readySince == null) {
      return;
    }
    // Only infer silence after continuously monitoring for the rule's duration.
    final eligible = _rules.where((r) => r.trigger != RuleTrigger.nodeSilent ||
      now.difference(readySince).inSeconds >= r.threshold * 3600).toList();
    _record(_engine.tick(eligible, now, monitoringConnected: true));
  }

  void _record(List<AutomationAlert> events) {
    if (events.isEmpty || _disposed) {
      return;
    }
    _alerts.insertAll(0, events.reversed);
    if (_alerts.length > 200) {
      _alerts.removeRange(200, _alerts.length);
    }
    final encoded = jsonEncode(_alerts.map((a) => {
      'ruleId': a.ruleId, 'nodeId': a.nodeId, 'message': a.message,
      'time': a.time.toIso8601String(),
    }).toList());
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
    super.dispose();
  }
}
