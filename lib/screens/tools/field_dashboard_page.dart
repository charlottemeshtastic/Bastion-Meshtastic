import 'package:flutter/material.dart';
import '../../models/mesh_node.dart';
import '../../services/node_archive.dart';
import '../../services/meshtastic/radio_session.dart';
import '../nodes/node_detail_page.dart';
import '../../services/field/coverage.dart';
import 'coverage_panel.dart';

class FieldDashboardPage extends StatefulWidget {
  const FieldDashboardPage({
    super.key,
    required this.session,
    required this.archive,
    this.coverage,
  });
  final RadioSession session;
  final NodeArchive archive;
  final CoverageRecorder? coverage;
  @override
  State<FieldDashboardPage> createState() => _FieldDashboardPageState();
}

class _FieldDashboardPageState extends State<FieldDashboardPage> {
  int? selectedRadio;
  String query = '';
  bool lowOnly = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.session, widget.archive]),
    builder: (context, _) {
      final radios = {
        ...widget.archive.radios,
        if (widget.session.localNode != null) widget.session.localNode!,
      }.toList()..sort();
      final radio = radios.contains(selectedRadio)
          ? selectedRadio
          : (radios.contains(widget.session.localNode)
                ? widget.session.localNode
                : radios.firstOrNull);
      final nodes = radio == null
          ? <MeshNode>[]
          : widget.archive.nodesFor(radio);
      final low = nodes
          .where((n) => !n.powered && n.battery != null && n.battery! < 20)
          .length;
      final filtered = nodes.where(
        (n) =>
            ('${n.displayName} ${n.id}').toLowerCase().contains(
              query.toLowerCase(),
            ) &&
            (!lowOnly || !n.powered && n.battery != null && n.battery! < 20),
      );
      final connected =
          radio == widget.session.localNode &&
          widget.session.status == RadioStatus.ready;
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'FIELD DASHBOARD',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            connected
                ? 'Connected · receiving observations'
                : 'Offline archive · connect to receive updates',
          ),
          if (widget.coverage != null)
            CoveragePanel(recorder: widget.coverage!),
          if (widget.archive.loading) const LinearProgressIndicator(),
          if (widget.archive.error != null)
            Text(
              widget.archive.error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          DropdownButton<int>(
            value: radio,
            isExpanded: true,
            hint: const Text('No saved radios yet'),
            items: [
              for (final r in radios)
                DropdownMenuItem(
                  value: r,
                  child: Text('Radio !${r.toRadixString(16).padLeft(8, '0')}'),
                ),
            ],
            onChanged: (v) => setState(() => selectedRadio = v),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${nodes.length} saved nodes · ${nodes.where((n) => n.hasPosition).length} positioned\n'
                '$low below 20% · ${nodes.where((n) => n.powered).length} externally powered\n'
                '${nodes.where((n) => n.battery == null && !n.powered).length} battery unknown',
                style: const TextStyle(height: 1.8),
              ),
            ),
          ),
          const Text(
            'Summary uses last reported values; it does not prove a node is currently reachable.',
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Find a node',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          FilterChip(
            label: const Text('Below 20% battery'),
            selected: lowOnly,
            onSelected: (v) => setState(() => lowOnly = v),
          ),
          if (nodes.isEmpty)
            const Text(
              'Connect a Meshtastic radio to save nodes and start collecting telemetry.',
            ),
          for (final node in filtered)
            Card(
              child: ListTile(
                leading: Icon(node.powered ? Icons.power : Icons.hub_outlined),
                title: Text(node.displayName),
                subtitle: Text(
                  '${node.id}\nLast heard: ${node.lastHeard?.toLocal() ?? 'unknown'}',
                ),
                trailing: Text(
                  node.powered
                      ? 'Powered'
                      : node.battery == null
                      ? '—'
                      : '${node.battery}%',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NodeDetailPage(
                      radio: radio!,
                      node: node,
                      archive: widget.archive,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'History is stored on this phone. Up to 2,000 nodes and 4,000 readings; '
            'readings older than 30 days are removed. Reinstalling or clearing app data removes it.',
          ),
          if (radio != null)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('CLEAR THIS RADIO’S NODE HISTORY'),
              onPressed: widget.archive.loading
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear saved node history?'),
                          content: const Text(
                            'This removes saved nodes and telemetry for the selected radio. '
                            'New observations will be saved while connected. Chats and automations are kept.',
                          ),
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
                        await widget.archive.clearRadio(radio);
                      }
                    },
            ),
        ],
      );
    },
  );
}
