import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/automations/automation_engine.dart';

class AutomationsPage extends StatefulWidget {
  const AutomationsPage({super.key});
  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  static const _storageKey = 'bastion.automation.rules.v1';
  List<AutomationRule> _rules = [];
  final _alerts = <AutomationAlert>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      final rules = saved == null ? <AutomationRule>[] :
        (jsonDecode(saved) as List).map((item) =>
          AutomationRule.fromJson(Map<String, dynamic>.from(item as Map))).toList();
      if (mounted) {
        setState(() { _rules = rules; _loading = false; });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false; _error = 'Could not load saved rules. Restart before changing rules.';
        });
      }
    }
  }

  Future<void> _save(List<AutomationRule> rules) async {
    setState(() { _saving = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_storageKey, jsonEncode(rules.map((r) => r.toJson()).toList()))) {
        throw StateError('Save failed');
      }
      if (mounted) {
        setState(() => _rules = rules);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Rules could not be saved. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _add() async {
    final trigger = await showDialog<RuleTrigger>(context: context, builder: (context) =>
      SimpleDialog(title: const Text('Choose a local alert'), children: [
        for (final item in RuleTrigger.values)
          SimpleDialogOption(onPressed: () => Navigator.pop(context, item),
            child: Text(switch (item) {
              RuleTrigger.batteryBelow => 'Battery below 20%',
              RuleTrigger.newNode => 'New node detected',
              RuleTrigger.nodeSilent => 'Node silent for 12 hours',
            })),
      ]));
    if (trigger == null || !mounted) return;
    final name = switch (trigger) {
      RuleTrigger.batteryBelow => 'Battery watch',
      RuleTrigger.newNode => 'New node detector',
      RuleTrigger.nodeSilent => 'Repeater watch',
    };
    await _save([..._rules, AutomationRule(id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name, trigger: trigger, threshold: trigger == RuleTrigger.nodeSilent ? 12 : 20)]);
  }

  void _simulate() {
    // Isolated engine: simulated observations never enter a future live session.
    final engine = AutomationEngine();
    final now = DateTime.now();
    final events = engine.observe(NodeObservation(id: 'DEMO-REPEATER',
      lastHeard: now, battery: 15), _rules, now);
    events.addAll(engine.tick(_rules, now.add(const Duration(hours: 13)),
      monitoringConnected: true));
    setState(() { _alerts.clear(); _alerts.addAll(events); });
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No enabled rules matched the demonstration.')));
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('LOCAL AUTOMATIONS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Saved on this device. No subscription, server or AI service required.'),
    const Card(child: Padding(padding: EdgeInsets.all(16),
      child: Text('Preview mode: rules can be tested with simulated data. Live radio monitoring, '
        'system notifications and background scheduling are not connected yet.'))),
    if (_loading) const LinearProgressIndicator(),
    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
    FilledButton.icon(onPressed: _loading || _saving || (_error?.contains('load') ?? false) ? null : _add,
      icon: const Icon(Icons.add), label: const Text('ADD RULE')),
    for (final rule in _rules)
      Card(child: Column(children: [
        SwitchListTile(title: Text(rule.name),
          subtitle: Text(switch (rule.trigger) {
            RuleTrigger.batteryBelow => 'Any node · below ${rule.threshold.toInt()}%',
            RuleTrigger.newNode => 'Any newly observed node',
            RuleTrigger.nodeSilent => 'Any node · ${rule.threshold.toInt()} hours silent',
          }), value: rule.enabled,
          onChanged: _saving ? null : (value) => _save(_rules.map((r) =>
            r.id == rule.id ? r.withEnabled(value) : r).toList())),
        TextButton(onPressed: _saving ? null : () =>
          _save(_rules.where((r) => r.id != rule.id).toList()), child: const Text('REMOVE')),
      ])),
    const SizedBox(height: 16),
    OutlinedButton.icon(onPressed: _loading || _saving ? null : _simulate,
      icon: const Icon(Icons.science_outlined), label: const Text('TEST WITH SIMULATED DATA')),
    if (_alerts.isNotEmpty) const Text('SIMULATED ALERTS'),
    for (final alert in _alerts)
      ListTile(leading: const Icon(Icons.notifications_outlined),
        title: Text(alert.message), subtitle: const Text('Demo only · no radio event')),
  ]);
}
