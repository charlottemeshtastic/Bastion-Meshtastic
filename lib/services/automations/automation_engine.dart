enum RuleTrigger { batteryBelow, newNode, nodeSilent }

class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.name,
    required this.trigger,
    required this.threshold,
    this.nodeId,
    this.radioId,
    this.enabled = true,
  });
  final String id;
  final String name;
  final RuleTrigger trigger;
  final double threshold;
  final String? nodeId;
  final int? radioId;
  final bool enabled;
  AutomationRule withEnabled(bool value) => AutomationRule(
    id: id,
    name: name,
    trigger: trigger,
    threshold: threshold,
    nodeId: nodeId,
    radioId: radioId,
    enabled: value,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'trigger': trigger.name,
    'threshold': threshold,
    'nodeId': nodeId,
    'radioId': radioId,
    'enabled': enabled,
  };
  factory AutomationRule.fromJson(Map<String, dynamic> json) => AutomationRule(
    id: json['id'] as String,
    name: json['name'] as String,
    trigger: RuleTrigger.values.byName(json['trigger'] as String),
    threshold: (json['threshold'] as num).toDouble(),
    nodeId: json['nodeId'] as String?,
    radioId: json['radioId'] as int?,
    enabled: json['enabled'] as bool,
  );

  String? get validationError {
    if (id.isEmpty || name.trim().isEmpty || name.length > 60) {
      return 'Give the rule a name of 1–60 characters.';
    }
    if (!threshold.isFinite) {
      return 'Enter a valid threshold.';
    }
    if (trigger == RuleTrigger.batteryBelow &&
        (threshold < 1 || threshold > 100)) {
      return 'Battery threshold must be 1–100%.';
    }
    if (trigger == RuleTrigger.nodeSilent &&
        (threshold < 0.25 || threshold > 168)) {
      return 'Silence duration must be 0.25–168 hours.';
    }
    if (nodeId != null && !RegExp(r'^![0-9a-f]{8}$').hasMatch(nodeId!)) {
      return 'Node ID must be ! followed by eight lowercase hex digits.';
    }
    if (radioId != null && (radioId! <= 0 || radioId! >= 0xffffffff)) {
      return 'Choose a valid radio identity.';
    }
    return null;
  }
}

class NodeObservation {
  const NodeObservation({
    required this.id,
    required this.lastHeard,
    this.battery,
  });
  final String id;
  final DateTime lastHeard;
  final double? battery;
}

class AutomationAlert {
  const AutomationAlert(
    this.ruleId,
    this.nodeId,
    this.message,
    this.time, {
    this.radioId,
  });
  final String ruleId;
  final String nodeId;
  final String message;
  final DateTime time;
  final int? radioId;
}

/// Pure local rule evaluation. Call observe only with verified radio data.
/// A condition alerts once, then rearms after recovery. Unknown battery never alerts.
class AutomationEngine {
  final Map<String, NodeObservation> _nodes = {};
  final Set<String> _active = {};
  void reset() {
    _nodes.clear();
    _active.clear();
  }

  void forgetRule(String id) =>
      _active.removeWhere((key) => key.startsWith('$id:'));

  void seed(NodeObservation node) {
    final old = _nodes[node.id];
    if (old == null || node.lastHeard.isAfter(old.lastHeard)) {
      _nodes[node.id] = node;
    }
  }

  List<AutomationAlert> observe(
    NodeObservation node,
    List<AutomationRule> rules,
    DateTime now,
  ) {
    // Ignore old/replayed observations instead of regressing node state.
    final previous = _nodes[node.id];
    if (previous != null && node.lastHeard.isBefore(previous.lastHeard))
      return [];
    final isNew = previous == null;
    _nodes[node.id] = node;
    final alerts = <AutomationAlert>[];
    for (final rule in rules) {
      if (!_matches(rule, node.id)) continue;
      final key = '${rule.id}:${node.id}';
      if (rule.trigger == RuleTrigger.newNode && isNew) {
        alerts.add(
          AutomationAlert(rule.id, node.id, 'New node: ${node.id}', now),
        );
      } else if (rule.trigger == RuleTrigger.batteryBelow &&
          node.battery != null) {
        final battery = node.battery!;
        if (battery >= 0 && battery <= 100) {
          _evaluate(
            key,
            battery < rule.threshold,
            rule,
            node,
            '${node.id} battery below ${rule.threshold}% (${battery.toInt()}%)',
            now,
            alerts,
          );
        }
      } else if (rule.trigger == RuleTrigger.nodeSilent &&
          now.difference(node.lastHeard).inSeconds < rule.threshold * 3600) {
        _active.remove(key);
      }
    }
    return alerts;
  }

  /// Evaluate a fresh battery measurement after the general node event, including
  /// packets within the same radio timestamp second.
  List<AutomationAlert> observeBattery(
    NodeObservation node,
    List<AutomationRule> rules,
    DateTime now,
  ) {
    final previous = _nodes[node.id];
    if (previous != null && node.lastHeard.isBefore(previous.lastHeard)) {
      return [];
    }
    _nodes[node.id] = node;
    final alerts = <AutomationAlert>[];
    final battery = node.battery;
    if (battery == null || !battery.isFinite || battery < 0 || battery > 100) {
      return alerts;
    }
    for (final rule in rules.where(
      (r) => r.trigger == RuleTrigger.batteryBelow,
    )) {
      if (_matches(rule, node.id)) {
        _evaluate(
          '${rule.id}:${node.id}',
          battery < rule.threshold,
          rule,
          node,
          '${node.id} battery below ${rule.threshold}% (${battery.toInt()}%)',
          now,
          alerts,
        );
      }
    }
    return alerts;
  }

  /// Silence checks require an active, synchronized radio session. A phone
  /// disconnect must not be interpreted as every repeater going offline.
  List<AutomationAlert> tick(
    List<AutomationRule> rules,
    DateTime now, {
    required bool monitoringConnected,
  }) {
    if (!monitoringConnected) return [];
    final alerts = <AutomationAlert>[];
    for (final rule in rules.where(
      (r) => r.trigger == RuleTrigger.nodeSilent,
    )) {
      for (final node in _nodes.values) {
        if (!_matches(rule, node.id) ||
            node.lastHeard.millisecondsSinceEpoch <= 0)
          continue;
        _evaluate(
          '${rule.id}:${node.id}',
          now.difference(node.lastHeard).inSeconds >= rule.threshold * 3600,
          rule,
          node,
          '${node.id} has not been heard for ${rule.threshold} hours',
          now,
          alerts,
        );
      }
    }
    return alerts;
  }

  bool _matches(AutomationRule rule, String id) =>
      rule.enabled && (rule.nodeId == null || rule.nodeId == id);

  void _evaluate(
    String key,
    bool condition,
    AutomationRule rule,
    NodeObservation node,
    String message,
    DateTime now,
    List<AutomationAlert> alerts,
  ) {
    if (!condition) {
      _active.remove(key);
      return;
    }
    if (_active.add(key))
      alerts.add(AutomationAlert(rule.id, node.id, message, now));
  }
}
