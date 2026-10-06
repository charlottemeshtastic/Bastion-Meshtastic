import 'dart:async';
import 'package:flutter/material.dart';
import 'services/meshtastic_ble_discovery.dart';
import 'screens/automations/automations_page.dart';
import 'screens/nodes/nodes_page.dart';
import 'screens/chats/chats_page.dart';
import 'services/messaging/chat_history.dart';
import 'models/chat_message.dart';
import 'screens/settings/radio_info_page.dart';
import 'services/meshtastic/radio_session.dart';
import 'services/automations/automation_controller.dart';
import 'services/automations/automation_engine.dart';
import 'services/alert_notifications.dart';
import 'services/bot/bot_controller.dart';
import 'services/connection/connection_manager.dart';
import 'services/field/offline_maps.dart';
import 'services/field/coverage.dart';
import 'services/node_archive.dart';
import 'models/telemetry_sample.dart';
import 'screens/map/mesh_map_page.dart';
import 'screens/tools/field_dashboard_page.dart';

void main() => runApp(const BastionMeshtasticApp());

class BastionMeshtasticApp extends StatelessWidget {
  const BastionMeshtasticApp({super.key});
  static const cyan = Color(0xFF9BC5B1);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bastion',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF20282B),
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: cyan,
            brightness: Brightness.dark,
          ).copyWith(
            primary: cyan,
            onPrimary: const Color(0xFF152D23),
            surface: const Color(0xFF293438),
            onSurface: const Color(0xFFE6E8E2),
            onSurfaceVariant: const Color(0xFFC1CBC5),
          ),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF20282B)),
    ),
    home: const BastionShell(),
  );
}

class BastionShell extends StatefulWidget {
  const BastionShell({super.key});

  @override
  State<BastionShell> createState() => _BastionShellState();
}

class _BastionShellState extends State<BastionShell>
    with WidgetsBindingObserver {
  int index = 0;
  final ble = MeshtasticBleDiscovery();
  final session = RadioSession();
  final automations = AutomationController();
  final chatHistory = ChatHistory();
  final nodeArchive = NodeArchive();
  late final AlertNotifications notifications;
  late final BotController bot;
  late final ConnectionManager connection;
  late final CoverageRecorder coverage;
  final offlineMaps = OfflineMaps();
  StreamSubscription<AutomationAlert>? _liveAlerts;
  StreamSubscription<TelemetrySample>? _telemetry;
  StreamSubscription<ChatMessage>? _chatEvents;
  StreamSubscription<dynamic>? _observations;
  Timer? _tick;
  bool _wasReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    connection = ConnectionManager(session);
    coverage = CoverageRecorder(session);
    unawaited(connection.initialize());
    unawaited(coverage.load());
    unawaited(offlineMaps.load());
    bot = BotController(session);
    unawaited(bot.load());
    notifications = AlertNotifications(
      onOpen: () {
        if (mounted) {
          setState(() => index = 4);
        }
      },
    );
    unawaited(notifications.load());
    _liveAlerts = automations.liveAlerts.listen((alert) {
      unawaited(notifications.showAlert(alert));
    });
    unawaited(automations.load());
    _chatEvents = session.messages.listen(chatHistory.upsert);
    unawaited(chatHistory.load());
    unawaited(nodeArchive.load());
    _telemetry = session.telemetry.listen((sample) {
      nodeArchive.record(sample);
      coverage.record(sample);
      automations.observeTelemetry(sample);
    });
    session.addListener(_sessionChanged);
    _observations = session.observations.listen((node) {
      automations.observe(node, batteryFresh: false);
      final radio = session.localNode;
      if (radio != null) {
        nodeArchive.observe(radio, node);
      }
    });
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      automations.tick(DateTime.now(), readySince: session.readySince);
    });
  }

  void _sessionChanged() {
    final ready = session.status == RadioStatus.ready;
    if (ready && !_wasReady) {
      automations.seed(session.nodes, radioId: session.localNode);
      nodeArchive.seed(session.localNode!, session.nodes);
    }
    _wasReady = ready;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (!connection.screenOff || state == AppLifecycleState.detached) {
        bot.pause();
      }
      unawaited(
        state == AppLifecycleState.detached
            ? connection.stop()
            : connection.onForeground(false),
      );
      if (ble.scanning) {
        unawaited(ble.stop());
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(connection.onForeground(true));
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
    unawaited(_chatEvents?.cancel());
    unawaited(_telemetry?.cancel());
    unawaited(_liveAlerts?.cancel());
    connection.dispose();
    coverage.dispose();
    offlineMaps.dispose();
    bot.dispose();
    notifications.dispose();
    nodeArchive.dispose();
    chatHistory.dispose();
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
          Text(
            'BASTION',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: BastionMeshtasticApp.cyan,
              letterSpacing: 2,
            ),
          ),
          Text(
            'OFFLINE MESH COMPANION',
            style: TextStyle(fontSize: 10, letterSpacing: 1.4),
          ),
        ],
      ),
    ),
    body: SafeArea(
      child: IndexedStack(
        index: index,
        children: [
          NodesPage(
            discovery: ble,
            session: session,
            archive: nodeArchive,
            connection: connection,
          ),
          ChatsPage(session: session, history: chatHistory),
          MeshMapPage(
            session: session,
            archive: nodeArchive,
            active: index == 2,
            offlineMaps: offlineMaps,
            coverage: coverage,
          ),
          FieldDashboardPage(
            session: session,
            archive: nodeArchive,
            coverage: coverage,
          ),
          AutomationsPage(
            controller: automations,
            session: session,
            archive: nodeArchive,
            notifications: notifications,
            bot: bot,
            connection: connection,
          ),
          RadioInfoPage(session: session, connection: connection),
        ],
      ),
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
