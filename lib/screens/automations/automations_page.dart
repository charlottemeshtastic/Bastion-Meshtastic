import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/mesh_node.dart';
import '../../services/automations/automation_engine.dart';
import '../../services/automations/automation_controller.dart';
import '../../services/meshtastic/radio_session.dart';
import '../../services/node_archive.dart';
import '../../services/alert_notifications.dart';
import 'rule_editor_page.dart';

class AutomationsPage extends StatefulWidget {
  const AutomationsPage({
    super.key,
    this.controller,
    this.session,
    this.archive,
    this.notifications,
  });
  final AutomationController? controller;
  final RadioSession? session;
  final NodeArchive? archive;
  final AlertNotifications? notifications;
  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  late final AutomationController _controller;
  final _demoAlerts = <AutomationAlert>[];
  bool currentRadioOnly = false;
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

  Future<void> _edit([AutomationRule? rule]) async {
    final radios = {
      ...?widget.archive?.radios,
      if (widget.session?.localNode != null) widget.session!.localNode!,
      for (final r in _controller.rules)
        if (r.radioId != null) r.radioId!,
    }.toList()..sort();
    final nodes = <int, MeshNode>{};
    for (final radio in radios) {
      for (final node in widget.archive?.nodesFor(radio) ?? <MeshNode>[]) {
        nodes[node.number] = node;
      }
    }
    for (final node in widget.session?.nodes ?? <MeshNode>[]) {
      nodes[node.number] = node;
    }
    final result = await Navigator.of(context).push<AutomationRule>(
      MaterialPageRoute(
        builder: (_) => RuleEditorPage(
          rule: rule,
          currentRadio: widget.session?.localNode,
          radios: radios,
          nodes: nodes.values.toList(),
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    await _controller.saveRules(
      rule == null
          ? [..._controller.rules, result]
          : _controller.rules.map((r) => r.id == rule.id ? result : r).toList(),
    );
  }

  void _simulate() {
    final now = DateTime.now();
    final events = <AutomationAlert>[];
    for (final rule in _controller.rules.where((r) => r.enabled)) {
      final engine = AutomationEngine();
      final id = rule.nodeId ?? 'DEMO-REPEATER';
      events.addAll(
        engine.observe(
          NodeObservation(
            id: id,
            lastHeard: now,
            battery: rule.trigger == RuleTrigger.batteryBelow
                ? rule.threshold - 1
                : null,
          ),
          [rule],
          now,
        ),
      );
      if (rule.trigger == RuleTrigger.nodeSilent) {
        events.addAll(
          engine.tick(
            [rule],
            now.add(Duration(seconds: (rule.threshold * 3600).ceil() + 1)),
            monitoringConnected: true,
          ),
        );
      }
    }
    setState(() {
      _demoAlerts.clear();
      _demoAlerts.addAll(events);
    });
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No enabled rules to simulate.')),
      );
    }
  }

  Future<void> _remove(AutomationRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${rule.name}?'),
        content: const Text('Saved alerts will remain in history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.saveRules(
        _controller.rules.where((r) => r.id != rule.id).toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      _controller,
      if (widget.session != null) widget.session!,
      if (widget.archive != null) widget.archive!,
      if (widget.notifications != null) widget.notifications!,
    ]),
    builder: (context, _) {
      final ready = widget.session?.status == RadioStatus.ready;
      final busy =
          _controller.loading || _controller.saving || _controller.loadFailed;
      final radio = widget.session?.localNode;
      final alerts = _controller.alerts.where(
        (a) => !currentRadioOnly || a.radioId == radio,
      );
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'LOCAL AUTOMATIONS',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Saved on this device. No subscription, server or AI service required.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                ready
                    ? 'Live monitoring while this app is open. Alerts are saved here. Silence checks require continuous monitoring. '
                          'Battery rules use fresh received measurements. Background monitoring is not enabled.'
                    : 'Monitoring paused. Connect a radio in NODES for live alerts, or test rules with isolated simulation.',
              ),
            ),
          ),
          if (_controller.loading) const LinearProgressIndicator(),
          if (widget.notifications != null) ...[
            SwitchListTile(
              title: const Text('Android notifications'),
              subtitle: Text(
                widget.notifications!.supported
                    ? 'Notify for new live alerts while this app is open and connected'
                    : 'Available on Android',
              ),
              value: widget.notifications!.enabled,
              onChanged:
                  widget.notifications!.loading ||
                      widget.notifications!.saving ||
                      !widget.notifications!.supported
                  ? null
                  : widget.notifications!.setEnabled,
            ),
            if (widget.notifications!.error != null)
              Text(
                widget.notifications!.error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            if (widget.notifications!.enabled)
              TextButton.icon(
                onPressed: widget.notifications!.saving
                    ? null
                    : widget.notifications!.test,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('SEND TEST NOTIFICATION'),
              ),
          ],
          if (_controller.error != null)
            Text(
              _controller.error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          FilledButton.icon(
            onPressed: busy || _controller.rules.length >= 50
                ? null
                : () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('ADD RULE'),
          ),
          Text('${_controller.rules.length}/50 saved rules'),
          for (final rule in _controller.rules)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(rule.name),
                    subtitle: Text(
                      [
                        rule.nodeId ?? 'Any node',
                        rule.radioId == null
                            ? 'any connected radio'
                            : 'radio !${rule.radioId!.toRadixString(16).padLeft(8, '0')}',
                        switch (rule.trigger) {
                          RuleTrigger.batteryBelow =>
                            'below ${rule.threshold}%',
                          RuleTrigger.newNode => 'newly observed',
                          RuleTrigger.nodeSilent =>
                            '${rule.threshold} hours silent',
                        },
                      ].join(' · '),
                    ),
                    value: rule.enabled,
                    onChanged: busy
                        ? null
                        : (v) => _controller.saveRules(
                            _controller.rules
                                .map(
                                  (r) => r.id == rule.id ? r.withEnabled(v) : r,
                                )
                                .toList(),
                          ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: busy ? null : () => _edit(rule),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('EDIT'),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _remove(rule),
                        child: const Text('REMOVE'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy ? null : _simulate,
            icon: const Icon(Icons.science_outlined),
            label: const Text('TEST WITH SIMULATED DATA'),
          ),
          if (_demoAlerts.isNotEmpty) const Text('SIMULATED ALERTS'),
          for (final alert in _demoAlerts)
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: Text(alert.message),
              subtitle: const Text('Demo only · no radio event or saved alert'),
            ),
          if (_controller.alerts.isNotEmpty) ...[
            const Text('LIVE ALERT HISTORY'),
            FilterChip(
              label: const Text('Selected radio only'),
              selected: currentRadioOnly,
              onSelected: radio == null
                  ? null
                  : (v) => setState(() => currentRadioOnly = v),
            ),
            for (final alert in alerts)
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(alert.message),
                subtitle: Text(
                  '${alert.time.toLocal()} · ${alert.radioId == null ? 'legacy alert · radio unknown' : 'radio !${alert.radioId!.toRadixString(16).padLeft(8, '0')}'}',
                ),
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear live alert history?'),
                          content: const Text('Rules will be kept.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('CANCEL'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('CLEAR'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _controller.clearHistory();
                      }
                    },
              child: const Text('CLEAR ALERT HISTORY'),
            ),
          ],
        ],
      );
    },
  );
}
