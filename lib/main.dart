import 'dart:async';
import 'package:flutter/material.dart';
import 'services/meshtastic_ble_discovery.dart';
import 'screens/automations/automations_page.dart';
import 'screens/nodes/nodes_page.dart';
import 'screens/settings/radio_info_page.dart';
import 'services/meshtastic/radio_session.dart';
import 'services/automations/automation_controller.dart';

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

class _BastionShellState extends State<BastionShell> with WidgetsBindingObserver {
  int index = 0;
  final ble = MeshtasticBleDiscovery();
  final session = RadioSession();
  final automations = AutomationController();
  StreamSubscription<dynamic>? _observations;
  Timer? _tick;
  bool _wasReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(automations.load());
    session.addListener(_sessionChanged);
    _observations = session.observations.listen(automations.observe);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      automations.tick(DateTime.now(), readySince: session.readySince);
    });
  }

  void _sessionChanged() {
    final ready = session.status == RadioStatus.ready;
    if (ready && !_wasReady) {
      automations.seed(session.nodes);
    }
    _wasReady = ready;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(session.disconnect());
      if (ble.scanning) {
        unawaited(ble.stop());
      }
    }
  }
  static const labels = ['NODES', 'CHATS', 'MAP', 'TOOLS', 'AUTO', 'SETTINGS'];
  static const icons = [
    Icons.hub_outlined,
    Icons.chat_bubble_outline,
    Icons.map_outlined,
    Icons.build_outlined,
    Icons.bolt_outlined,
    Icons.settings_outlined,
  ];

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    unawaited(_observations?.cancel());
    session.removeListener(_sessionChanged);
    session.dispose();
    automations.dispose();
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
        NodesPage(discovery: ble, session: session),
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
        AutomationsPage(controller: automations, session: session),
        RadioInfoPage(session: session),
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
