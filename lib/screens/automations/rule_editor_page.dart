import 'package:flutter/material.dart';
import '../../models/mesh_node.dart';
import '../../services/automations/automation_engine.dart';

String ruleTriggerName(RuleTrigger trigger) => switch (trigger) {
  RuleTrigger.batteryBelow => 'Low battery',
  RuleTrigger.newNode => 'New node',
  RuleTrigger.nodeSilent => 'Node silence',
};

class RuleEditorPage extends StatefulWidget {
  const RuleEditorPage({
    super.key,
    this.rule,
    this.currentRadio,
    required this.radios,
    required this.nodes,
  });
  final AutomationRule? rule;
  final int? currentRadio;
  final List<int> radios;
  final List<MeshNode> nodes;
  @override
  State<RuleEditorPage> createState() => _RuleEditorPageState();
}

class _RuleEditorPageState extends State<RuleEditorPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController threshold;
  late final TextEditingController target;
  late RuleTrigger trigger;
  late int radio;
  String? error;
  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    trigger = rule?.trigger ?? RuleTrigger.batteryBelow;
    name = TextEditingController(text: rule?.name ?? 'Battery watch');
    threshold = TextEditingController(text: (rule?.threshold ?? 20).toString());
    target = TextEditingController(text: rule?.nodeId ?? '');
    radio = rule == null ? widget.currentRadio ?? -1 : rule.radioId ?? -1;
  }

  @override
  void dispose() {
    name.dispose();
    threshold.dispose();
    target.dispose();
    super.dispose();
  }

  void save() {
    if (!form.currentState!.validate()) {
      return;
    }
    var nodeId = target.text.trim().toLowerCase();
    if (nodeId.isNotEmpty && !nodeId.startsWith('!')) {
      nodeId = '!$nodeId';
    }
    final rule = AutomationRule(
      id: widget.rule?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.text.trim(),
      trigger: trigger,
      threshold: trigger == RuleTrigger.newNode
          ? 0
          : double.tryParse(threshold.text.trim()) ?? double.nan,
      nodeId: nodeId.isEmpty ? null : nodeId,
      radioId: radio == -1 ? null : radio,
      enabled: widget.rule?.enabled ?? true,
    );
    if (rule.validationError != null) {
      setState(() => error = rule.validationError);
      return;
    }
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    final radios = {...widget.radios, if (radio != -1) radio}.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.rule == null ? 'Create local rule' : 'Edit local rule',
        ),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            TextFormField(
              controller: name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Rule name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter a rule name.' : null,
            ),
            DropdownButtonFormField<RuleTrigger>(
              initialValue: trigger,
              decoration: const InputDecoration(labelText: 'Trigger'),
              items: [
                for (final t in RuleTrigger.values)
                  DropdownMenuItem(value: t, child: Text(ruleTriggerName(t))),
              ],
              onChanged: (v) {
                if (v == null) {
                  return;
                }
                setState(() {
                  if ([
                    'Battery watch',
                    'New node detector',
                    'Repeater watch',
                  ].contains(name.text)) {
                    name.text = switch (v) {
                      RuleTrigger.batteryBelow => 'Battery watch',
                      RuleTrigger.newNode => 'New node detector',
                      RuleTrigger.nodeSilent => 'Repeater watch',
                    };
                  }
                  trigger = v;
                  threshold.text = v == RuleTrigger.nodeSilent ? '12' : '20';
                  error = null;
                });
              },
            ),
            if (trigger != RuleTrigger.newNode)
              TextFormField(
                controller: threshold,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: trigger == RuleTrigger.batteryBelow
                      ? 'Battery threshold (%)'
                      : 'Silence duration (hours)',
                  helperText: trigger == RuleTrigger.batteryBelow
                      ? '1–100%; alerts below this value'
                      : '0.25–168 hours; 0.5 means 30 minutes',
                ),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || !n.isFinite) {
                    return 'Enter a number.';
                  }
                  if (trigger == RuleTrigger.batteryBelow &&
                      (n < 1 || n > 100)) {
                    return 'Use 1–100%.';
                  }
                  if (trigger == RuleTrigger.nodeSilent &&
                      (n < 0.25 || n > 168)) {
                    return 'Use 0.25–168 hours.';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: radio,
              decoration: const InputDecoration(labelText: 'Radio scope'),
              items: [
                const DropdownMenuItem(
                  value: -1,
                  child: Text('Any connected radio'),
                ),
                for (final r in radios)
                  DropdownMenuItem(
                    value: r,
                    child: Text(
                      'Radio !${r.toRadixString(16).padLeft(8, '0')}',
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => radio = v ?? -1),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: target,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Target node ID (optional)',
                helperText: 'Leave empty for any node. Example: !a1b2c3d4',
              ),
              validator: (v) {
                final text = v?.trim().toLowerCase() ?? '';
                return text.isEmpty || RegExp(r'^!?[0-9a-f]{8}$').hasMatch(text)
                    ? null
                    : 'Use eight hexadecimal digits, with optional ! prefix.';
              },
            ),
            if (widget.nodes.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Quick targets from saved or connected nodes'),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                    label: const Text('Any node'),
                    onPressed: () => target.clear(),
                  ),
                  for (final node in widget.nodes.take(30))
                    ActionChip(
                      label: Text(node.displayName),
                      onPressed: () => target.text = node.id,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Action: save an in-app alert. Rules run while Bastion is open and connected. '
                  'Silence rules wait for continuous monitoring for the chosen duration. '
                  'Downloaded node history does not fire new-node alerts.',
                ),
              ),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
            FilledButton.icon(
              onPressed: save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('SAVE RULE'),
            ),
          ],
        ),
      ),
    );
  }
}
