import 'package:flutter/material.dart';
import '../../services/meshtastic_ble_discovery.dart';
import '../../services/meshtastic/ble_radio_transport.dart';
import '../../services/meshtastic/radio_session.dart';
import '../../services/node_archive.dart';
import 'node_detail_page.dart';
import '../../services/connection/connection_manager.dart';
import 'connection_panel.dart';

class NodesPage extends StatelessWidget {
  const NodesPage({
    super.key,
    required this.discovery,
    required this.session,
    this.archive,
    this.connection,
  });
  final MeshtasticBleDiscovery discovery;
  final RadioSession session;
  final NodeArchive? archive;
  final ConnectionManager? connection;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([discovery, session, ?connection]),
    builder: (context, _) {
      final busy =
          session.status == RadioStatus.connecting ||
          session.status == RadioStatus.downloading;
      final ready = session.status == RadioStatus.ready;
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'RADIO CONNECTION',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(switch (session.status) {
            RadioStatus.disconnected =>
              'Disconnected · scan and select your radio',
            RadioStatus.connecting =>
              'Connecting · accept the Bluetooth pairing prompt if shown',
            RadioStatus.downloading =>
              'Downloading radio configuration and node database…',
            RadioStatus.ready => 'Ready · verified Meshtastic session',
            RadioStatus.error => 'Connection needs attention',
          }),
          if (busy) const LinearProgressIndicator(),
          if (session.error != null)
            Text(
              session.error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          if (ready || busy)
            OutlinedButton(
              onPressed: connection?.stop ?? session.disconnect,
              child: const Text('DISCONNECT'),
            ),
          FilledButton.icon(
            onPressed: discovery.scanning || busy || ready
                ? null
                : discovery.scan,
            icon: const Icon(Icons.bluetooth_searching),
            label: Text(
              discovery.scanning ? 'SCANNING…' : 'SCAN MESHTASTIC RADIOS',
            ),
          ),
          if (discovery.scanning)
            TextButton(
              onPressed: discovery.stop,
              child: const Text('STOP SCAN'),
            ),
          if (discovery.error != null)
            Text(
              discovery.error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          if (!ready && discovery.results.isEmpty && !discovery.scanning)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Enable Bluetooth on your radio and phone, then scan.',
              ),
            ),
          if (!ready)
            for (final item in discovery.results)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(
                    item.advertisementData.advName.isNotEmpty
                        ? item.advertisementData.advName
                        : 'Meshtastic radio candidate',
                  ),
                  subtitle: Text(
                    '${item.device.remoteId.str} · BLE ${item.rssi} dBm',
                  ),
                  trailing: const Icon(Icons.link),
                  onTap: busy
                      ? null
                      : () async {
                          await discovery.stop();
                          if (connection != null) {
                            await connection!.connect(
                              () => BleRadioTransport(item.device),
                            );
                          } else {
                            await session.connect(
                              BleRadioTransport(item.device),
                            );
                          }
                        },
                ),
              ),
          if (connection != null) ConnectionPanel(manager: connection!),
          const SizedBox(height: 20),
          Text(
            'MESH NODES (${session.nodes.length})',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (!ready && session.nodes.isNotEmpty)
            const Text('Cached view from this session · monitoring is paused'),
          if (session.nodes.isEmpty)
            const Text(
              'Verified mesh nodes appear after the configuration download.',
            ),
          for (final node in session.nodes)
            Card(
              child: ListTile(
                leading: Icon(
                  node.number == session.localNode
                      ? Icons.router
                      : Icons.hub_outlined,
                ),
                title: Text(node.displayName),
                subtitle: Text(
                  [
                    node.id,
                    if (node.lastHeard != null)
                      'Heard ${node.lastHeard!.toLocal()}'
                    else
                      'Last heard unknown',
                    if (node.snr != null)
                      'SNR ${node.snr!.toStringAsFixed(1)} dB',
                    if (node.rssi != null) 'RSSI ${node.rssi} dBm',
                    if (node.hops != null) '${node.hops} hops',
                    if (node.viaMqtt) 'via MQTT',
                    if (node.latitude != null && node.longitude != null)
                      '${node.latitude!.toStringAsFixed(5)}, ${node.longitude!.toStringAsFixed(5)}',
                  ].join(' · '),
                ),
                trailing: Text(
                  node.powered
                      ? 'Powered'
                      : node.battery == null
                      ? '—'
                      : '${node.battery}%',
                ),
                onTap: archive == null || session.localNode == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NodeDetailPage(
                            radio: session.localNode!,
                            node: node,
                            archive: archive!,
                          ),
                        ),
                      ),
              ),
            ),
          if (session.firmware != null)
            Text('Radio firmware: ${session.firmware}'),
          const SizedBox(height: 16),
          const Text(
            'Development build · hardware validation pending. '
            'Screen-off monitoring requires the explicit Android connection service.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      );
    },
  );
}
