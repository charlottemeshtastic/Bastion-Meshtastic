import 'package:flutter/material.dart';
import 'services/meshtastic_ble_discovery.dart';

void main() => runApp(const BastionMeshtasticApp());

class BastionMeshtasticApp extends StatelessWidget {
  const BastionMeshtasticApp({super.key});
  static const cyan = Color(0xFF18D3D3);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bastion Meshtastic',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0E11),
      colorScheme: ColorScheme.fromSeed(
        seedColor: cyan,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B0E11)),
    ),
    home: const BastionShell(),
  );
}

class BastionShell extends StatefulWidget {
  const BastionShell({super.key});

  @override
  State<BastionShell> createState() => _BastionShellState();
}

class _BastionShellState extends State<BastionShell> {
  int index = 0;
  final ble = MeshtasticBleDiscovery();
  static const labels = ['NODES', 'CHATS', 'MAP', 'TOOLS', 'SETTINGS'];
  static const icons = [
    Icons.hub_outlined,
    Icons.chat_bubble_outline,
    Icons.map_outlined,
    Icons.build_outlined,
    Icons.settings_outlined,
  ];

  @override
  void dispose() {
    ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BASTION',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: BastionMeshtasticApp.cyan,
                  letterSpacing: 2)),
          Text('MESHTASTIC EDITION',
              style: TextStyle(fontSize: 10, letterSpacing: 1.4)),
        ],
      ),
    ),
    body: SafeArea(
      child: IndexedStack(index: index, children: [
        _NodesPage(discovery: ble),
        const _FeaturePage(
          icon: Icons.chat_bubble_outline,
          title: 'CHATS',
          detail: 'Direct messages and channel messaging will be enabled after Meshtastic transport and protobuf integration.',
        ),
        const _FeaturePage(
          icon: Icons.map_outlined,
          title: 'MESH MAP',
          detail: 'Verified mesh node positions, telemetry and offline maps are next. BLE scan results are not mesh nodes.',
        ),
        const _FeaturePage(
          icon: Icons.build_outlined,
          title: 'FIELD TOOLS',
          detail: 'Device configuration, traceroute, diagnostics, telemetry and coverage capture are planned.',
        ),
        const _FeaturePage(
          icon: Icons.settings_outlined,
          title: 'SETTINGS',
          detail: 'Connection preferences, channel configuration, privacy and app information will be added here.',
        ),
      ]),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: [
        for (var i = 0; i < labels.length; i++)
          NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
      ],
    ),
  );
}

class _NodesPage extends StatelessWidget {
  const _NodesPage({required this.discovery});
  final MeshtasticBleDiscovery discovery;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: discovery,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _Header(
          title: 'RADIO DISCOVERY',
          detail: 'Scan for nearby Bluetooth LE devices. Meshtastic identity and protocol connection are not implemented yet.',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: discovery.scanning ? null : discovery.scan,
          icon: Icon(discovery.scanning
              ? Icons.hourglass_top
              : Icons.bluetooth_searching),
          label: Text(discovery.scanning
              ? 'SCANNING…'
              : 'SCAN NEARBY DEVICES'),
        ),
        if (discovery.scanning)
          TextButton(
            onPressed: discovery.stop,
            child: const Text('STOP SCAN'),
          ),
        if (discovery.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              discovery.error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        const SizedBox(height: 16),
        if (discovery.results.isEmpty)
          const Text(
            'No BLE devices discovered yet.',
            style: TextStyle(color: Colors.white70),
          )
        else
          for (final item in discovery.results)
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.bluetooth,
                  color: BastionMeshtasticApp.cyan,
                ),
                title: Text(item.advertisementData.advName.isNotEmpty
                    ? item.advertisementData.advName
                    : 'Unnamed BLE device'),
                subtitle: Text(item.device.remoteId.str),
                trailing: Text('${item.rssi} dBm'),
              ),
            ),
        const SizedBox(height: 16),
        const Text(
          'Discovery only. Do not use this build for emergency communication.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF12171C),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: BastionMeshtasticApp.cyan.withValues(alpha: 0.5),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: BastionMeshtasticApp.cyan,
          ),
        ),
        const SizedBox(height: 8),
        Text(detail, style: const TextStyle(height: 1.5)),
      ],
    ),
  );
}

class _FeaturePage extends StatelessWidget {
  const _FeaturePage({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const SizedBox(height: 20),
      Icon(icon, size: 48, color: BastionMeshtasticApp.cyan),
      const SizedBox(height: 16),
      _Header(title: title, detail: detail),
    ],
  );
}
