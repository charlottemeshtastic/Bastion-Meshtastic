import 'package:flutter/material.dart';

import 'services/meshtastic_node_database.dart';
import 'services/meshtastic_radio_coordinator.dart';
import 'services/meshtastic_traceroute.dart';

/// Picks a mesh node and shows the route to it and back with per-hop SNR.
class TraceroutePage extends StatefulWidget {
  const TraceroutePage({super.key, required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  State<TraceroutePage> createState() => _TraceroutePageState();
}

class _TraceroutePageState extends State<TraceroutePage> {
  int? _target;
  TracerouteResult? _result;
  Object? _error;
  bool _running = false;

  Future<void> _run() async {
    final target = _target;
    if (target == null) return;
    setState(() {
      _running = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.radio.traceroute(target);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _name(int num) {
    if (num == widget.radio.localNodeNum) return 'This radio';
    for (final node in widget.radio.nodes) {
      if (node.num == num) return node.displayName;
    }
    return '!${num.toRadixString(16).padLeft(8, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Traceroute')),
        body: AnimatedBuilder(
          animation: widget.radio,
          builder: (context, _) {
            final local = widget.radio.localNodeNum;
            final nodes = widget.radio.nodes.where((n) => n.num != local).toList()
              ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Destination node'),
                  items: [
                    for (final MeshtasticNode node in nodes)
                      DropdownMenuItem(value: node.num, child: Text(node.displayName)),
                  ],
                  onChanged: _running ? null : (v) => setState(() => _target = v),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _target != null && !_running && widget.radio.canTraceroute ? _run : null,
                  icon: _running
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.route),
                  label: Text(_running ? 'Tracing… up to 60 s' : 'Run traceroute'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Firmware limits how often traceroutes can run. Each one uses '
                  'airtime on every relay, so avoid repeating them quickly.',
                  style: TextStyle(color: Colors.white70),
                ),
                if (!widget.radio.canTraceroute && !_running)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Connect to a radio and wait for READY.'),
                  ),
                if (nodes.isEmpty && widget.radio.isReady)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('No other nodes heard yet.'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text('$_error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (_result case final result?) ...[
                  const SizedBox(height: 16),
                  Text(
                    result.intermediateHops == 0
                        ? 'Direct — no relays'
                        : '${result.intermediateHops} relay${result.intermediateHops == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  _RouteCard(
                    title: 'Route there',
                    start: 'This radio',
                    hops: result.towards,
                    name: _name,
                  ),
                  if (result.back.isNotEmpty)
                    _RouteCard(
                      title: 'Route back',
                      start: _name(_target!),
                      hops: result.back,
                      name: _name,
                    )
                  else
                    const Card(
                      child: ListTile(
                        title: Text('Route back'),
                        subtitle: Text('Not reported by this firmware'),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      );
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.title,
    required this.start,
    required this.hops,
    required this.name,
  });

  final String title;
  final String start;
  final List<TracerouteHop> hops;
  final String Function(int) name;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(start),
              for (final hop in hops)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '↓ ${hop.snrDb == null ? 'SNR unknown' : '${hop.snrDb!.toStringAsFixed(1)} dB'}\n'
                    '${name(hop.nodeNum)}',
                  ),
                ),
            ],
          ),
        ),
      );
}
