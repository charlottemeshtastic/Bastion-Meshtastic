import 'package:flutter/material.dart';

import 'services/bastion_geo.dart';
import 'services/meshtastic_radio_coordinator.dart';

/// Range Test log and Store & Forward history requests.
class MeshToolsPage extends StatelessWidget {
  const MeshToolsPage({super.key, required this.radio, this.initialTab = 0});

  final MeshtasticRadioCoordinator radio;
  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Mesh tools'),
            bottom: const TabBar(tabs: [Tab(text: 'Range test'), Tab(text: 'Store & forward')]),
          ),
          body: AnimatedBuilder(
            animation: radio,
            builder: (context, _) => TabBarView(
              children: [_RangeTestTab(radio: radio), _StoreForwardTab(radio: radio)],
            ),
          ),
        ),
      );
}

String _nameOf(MeshtasticRadioCoordinator radio, int num) {
  for (final node in radio.nodes) {
    if (node.num == num) return node.displayName;
  }
  return '!${num.toRadixString(16).padLeft(8, '0')}';
}

class _RangeTestTab extends StatelessWidget {
  const _RangeTestTab({required this.radio});

  final MeshtasticRadioCoordinator radio;

  String? _distance(int from) {
    final local = radio.localNode;
    if (local == null || !local.hasPosition) return null;
    for (final node in radio.nodes) {
      if (node.num == from && node.hasPosition) {
        final m = BastionGeo.distanceMeters(local.latitude!, local.longitude!, node.latitude!, node.longitude!);
        return m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(2)} km';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final entries = radio.rangeTest.reversed.toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Set one radio as the Range Test sender (Settings → Change radio settings → '
          'Rangetest: enabled, sender interval). Carry this radio away from it; each '
          'packet heard appears here with signal and distance. Gaps in the sequence '
          'number are lost packets.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text('${entries.length} packets heard', style: const TextStyle(fontWeight: FontWeight.bold))),
            TextButton(onPressed: entries.isEmpty ? null : radio.clearRangeTest, child: const Text('Clear')),
          ],
        ),
        for (final e in entries)
          Card(
            child: ListTile(
              dense: true,
              title: Text('${_nameOf(radio, e.from)} • ${e.text}'),
              subtitle: Text([
                e.receivedAt.toLocal().toString().substring(11, 19),
                if (e.snr != null) 'SNR ${e.snr!.toStringAsFixed(1)} dB',
                if (e.rssi != null) 'RSSI ${e.rssi} dBm',
                ?_distance(e.from),
              ].join(' • ')),
            ),
          ),
      ],
    );
  }
}

class _StoreForwardTab extends StatefulWidget {
  const _StoreForwardTab({required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  State<_StoreForwardTab> createState() => _StoreForwardTabState();
}

class _StoreForwardTabState extends State<_StoreForwardTab> {
  Duration _window = const Duration(hours: 2);

  static const _windows = <(String, Duration)>[
    ('Last 30 minutes', Duration(minutes: 30)),
    ('Last 2 hours', Duration(hours: 2)),
    ('Last 8 hours', Duration(hours: 8)),
    ('Last 24 hours', Duration(hours: 24)),
  ];

  @override
  Widget build(BuildContext context) {
    final radio = widget.radio;
    final routers = radio.storeForwardRouters;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'A Store & Forward router keeps recent messages and can replay the ones '
          'you missed while out of range. Replayed messages appear in Chats.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Duration>(
          initialValue: _window,
          decoration: const InputDecoration(labelText: 'Replay messages from'),
          items: [for (final (label, d) in _windows) DropdownMenuItem(value: d, child: Text(label))],
          onChanged: (v) => setState(() => _window = v ?? _window),
        ),
        const SizedBox(height: 12),
        if (radio.lastStoreForwardReply != null)
          Card(child: ListTile(leading: const Icon(Icons.info_outline), title: Text(radio.lastStoreForwardReply!))),
        if (routers.isEmpty)
          const Text(
            'No Store & Forward router heard yet. Routers announce themselves with a '
            'heartbeat every few minutes, if heartbeats are enabled on them.',
            style: TextStyle(color: Colors.white60),
          ),
        for (final router in routers)
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(_nameOf(radio, router.nodeNum)),
              subtitle: Text('Heard ${router.lastHeard.toLocal().toString().substring(11, 16)}'),
              trailing: FilledButton.tonal(
                onPressed: radio.isReady
                    ? () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await radio.requestStoredMessages(router.nodeNum, _window);
                          messenger.showSnackBar(const SnackBar(content: Text('History requested.')));
                        } catch (error) {
                          messenger.showSnackBar(SnackBar(content: Text('Request failed: $error')));
                        }
                      }
                    : null,
                child: const Text('Replay'),
              ),
            ),
          ),
      ],
    );
  }
}
