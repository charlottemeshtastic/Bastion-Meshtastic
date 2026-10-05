import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/automations/automation_engine.dart';
import '../../services/automations/automation_controller.dart';
import '../../services/meshtastic/radio_session.dart';

class AutomationsPage extends StatefulWidget {
  const AutomationsPage({super.key, this.controller, this.session});
  final AutomationController? controller;
  final RadioSession? session;
  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  late final AutomationController _controller;
  final _demoAlerts = <AutomationAlert>[];
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AutomationController();
    if (widget.controller == null) {
      unawaited(_controller.load());
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
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
    if (trigger == null || !mounted) {
      return;
    }
    final name = switch (trigger) {
      RuleTrigger.batteryBelow => 'Battery watch',
      RuleTrigger.newNode => 'New node detector',
      RuleTrigger.nodeSilent => 'Repeater watch',
    };
    await _controller.saveRules([..._controller.rules, AutomationRule(
      id: DateTime.now().microsecondsSinceEpoch.toString(), name: name,
      trigger: trigger, threshold: trigger == RuleTrigger.nodeSilent ? 12 : 20)]);
  }

  void _simulate() {
    final engine = AutomationEngine();
    final now = DateTime.now();
    final events = engine.observe(NodeObservation(id: 'DEMO-REPEATER',
      lastHeard: now, battery: 15), _controller.rules, now);
    events.addAll(engine.tick(_controller.rules, now.add(const Duration(hours: 13)),
      monitoringConnected: true));
    setState(() { _demoAlerts.clear(); _demoAlerts.addAll(events); });
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No enabled rules matched the demonstration.')));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_controller, if (widget.session != null) widget.session!]),
    builder: (context, _) {
      final ready = widget.session?.status == RadioStatus.ready;
      final busy = _controller.loading || _controller.saving || _controller.loadFailed;
      return ListView(padding: const EdgeInsets.all(18), children: [
        const Text('LOCAL AUTOMATIONS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Saved on this device. No subscription, server or AI service required.'),
        Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Text(ready
            ? 'Live monitoring while this app is open. Alerts appear here and are saved locally. '
              'Silence checks require continuous monitoring. System notifications and background scheduling are next.'
            : 'Monitoring paused. Connect a radio in NODES to receive live alerts. '
              'You can also test with isolated simulated data.'))),
        if (_controller.loading) const LinearProgressIndicator(),
        if (_controller.error != null)
          Text(_controller.error!, style: const TextStyle(color: Colors.orangeAccent)),
        FilledButton.icon(onPressed: busy ? null : _add,
          icon: const Icon(Icons.add), label: const Text('ADD RULE')),
        for (final rule in _controller.rules)
          Card(child: Column(children: [
            SwitchListTile(title: Text(rule.name),
              subtitle: Text(switch (rule.trigger) {
                RuleTrigger.batteryBelow => 'Any node · below ${rule.threshold.toInt()}%',
                RuleTrigger.newNode => 'Any newly observed node',
                RuleTrigger.nodeSilent => 'Any node · ${rule.threshold.toInt()} hours silent',
              }), value: rule.enabled,
              onChanged: busy ? null : (value) => _controller.saveRules(
                _controller.rules.map((r) => r.id == rule.id ? r.withEnabled(value) : r).toList())),
            TextButton(onPressed: busy ? null : () => _controller.saveRules(
              _controller.rules.where((r) => r.id != rule.id).toList()),
              child: const Text('REMOVE')),
          ])),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: busy ? null : _simulate,
          icon: const Icon(Icons.science_outlined), label: const Text('TEST WITH SIMULATED DATA')),
        if (_demoAlerts.isNotEmpty) const Text('SIMULATED ALERTS'),
        for (final alert in _demoAlerts)
          ListTile(leading: const Icon(Icons.science_outlined), title: Text(alert.message),
            subtitle: const Text('Demo only · no radio event')),
        if (_controller.alerts.isNotEmpty) const Text('LIVE ALERT HISTORY'),
        for (final alert in _controller.alerts)
          ListTile(leading: const Icon(Icons.notifications_outlined),
            title: Text(alert.message), subtitle: Text(alert.time.toLocal().toString())),
      ]);
    });
}
