import 'package:flutter/material.dart';
import 'services/meshtastic_ble_discovery.dart';
import 'services/meshtastic_connection_controller.dart';
import 'services/meshtastic_messaging_service.dart';
import 'services/meshtastic_radio_coordinator.dart';

void main() => runApp(const BastionMeshtasticApp());

class BastionMeshtasticApp extends StatelessWidget {
  const BastionMeshtasticApp({super.key});
  static const cyan = Color(0xFF18D3D3);
  static const panel = Color(0xFF12171C);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bastion Meshtastic',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0E11),
      colorScheme: ColorScheme.fromSeed(seedColor: cyan, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B0E11)),
      cardTheme: CardThemeData(
        color: panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
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
  final radio = MeshtasticRadioCoordinator();
  bool botMode = false;
  bool lowPowerMode = false;
  String awayReply = 'Bastion is monitoring the mesh. I will reply when available.';

  static const labels = ['NODES', 'CHATS', 'MAP', 'TOOLS', 'SETTINGS'];
  static const icons = [
    Icons.hub_outlined, Icons.chat_bubble_outline, Icons.map_outlined,
    Icons.build_outlined, Icons.settings_outlined,
  ];

  @override
  void dispose() {
    ble.dispose();
    radio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BASTION', style: TextStyle(fontWeight: FontWeight.w900,
          color: BastionMeshtasticApp.cyan, letterSpacing: 2)),
        Text('MESHTASTIC EDITION', style: TextStyle(fontSize: 10, letterSpacing: 1.4)),
      ]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: AnimatedBuilder(
            animation: radio,
            builder: (context, _) => Chip(
              avatar: Icon(
                radio.isReady ? Icons.bluetooth_connected : Icons.radio_button_checked,
                size: 16,
              ),
              label: Text(_connectionLabel(radio.connection.state)),
              side: BorderSide(color: Colors.white.withValues(alpha: .15)),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(child: IndexedStack(index: index, children: [
      _NodesPage(discovery: ble, radio: radio, onOpenTools: () => setState(() => index = 3)),
      _ChatsPage(
        radio: radio,
        botMode: botMode,
        awayReply: awayReply,
        onBotModeChanged: (value) => setState(() => botMode = value),
        onAwayReplyChanged: (value) => setState(() => awayReply = value),
      ),
      const _MapPage(),
      _ToolsPage(discovery: ble),
      _SettingsPage(
        lowPowerMode: lowPowerMode,
        onLowPowerChanged: (value) => setState(() => lowPowerMode = value),
      ),
    ])),
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
  const _NodesPage({
    required this.discovery,
    required this.radio,
    required this.onOpenTools,
  });
  final MeshtasticBleDiscovery discovery;
  final MeshtasticRadioCoordinator radio;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([discovery, radio]),
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Header(icon: Icons.radar, title: 'MESH COMMAND',
          detail: 'Find a nearby radio, inspect Bluetooth signal strength, and prepare for a verified Meshtastic session.'),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Stat(label: 'BLE DEVICES', value: '${discovery.results.length}')),
          const SizedBox(width: 10),
          Expanded(child: _Stat(label: 'MESH NODES', value: '${radio.nodes.length}')),
          const SizedBox(width: 10),
          Expanded(child: _Stat(
            label: 'STATUS',
            value: _connectionLabel(radio.connection.state),
          )),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: discovery.scanning ? null : discovery.scan,
          icon: Icon(discovery.scanning ? Icons.hourglass_top : Icons.bluetooth_searching),
          label: Text(discovery.scanning ? 'SCANNING…' : 'SCAN FOR RADIOS'),
        ),
        if (discovery.scanning)
          TextButton(onPressed: discovery.stop, child: const Text('STOP SCAN')),
        if (discovery.error != null)
          _Notice(text: discovery.error!, icon: Icons.warning_amber),
        const SizedBox(height: 10),
        if (discovery.results.isEmpty)
          const _EmptyState(icon: Icons.bluetooth_disabled,
            title: 'No radios discovered yet',
            detail: 'Tap SCAN FOR RADIOS. Nearby BLE devices will appear here with live RSSI.')
        else
          for (final item in discovery.results)
            Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.router)),
              title: Text(item.name),
              subtitle: Text(
                '${item.id}\n${item.advertisesMeshtastic ? 'Meshtastic service advertised' : _rssiLabel(item.rssi)}',
              ),
              isThreeLine: true,
              trailing: radio.isReady && radio.connection.deviceName == item.name
                  ? IconButton(
                      tooltip: 'Disconnect',
                      onPressed: radio.busy ? null : radio.disconnect,
                      icon: const Icon(Icons.link_off),
                    )
                  : FilledButton(
                      onPressed: radio.busy
                          ? null
                          : () async {
                              try {
                                await radio.connect(item);
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Connection failed: $error')),
                                  );
                                }
                              }
                            },
                      child: const Text('CONNECT'),
                    ),
            )),
        if (radio.connection.error != null)
          _Notice(text: radio.connection.error!, icon: Icons.error_outline),
        if (radio.nodes.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('LIVE MESH NODES',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(height: 6),
          for (final node in radio.nodes)
            Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.cell_tower)),
              title: Text(node.displayName),
              subtitle: Text([
                if (node.shortName?.isNotEmpty ?? false) node.shortName!,
                node.id ?? '!${node.num.toRadixString(16).padLeft(8, '0')}',
              ].join(' • ')),
              trailing: node.hardwareModel == null
                  ? null
                  : Text('HW ${node.hardwareModel}'),
            )),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: onOpenTools,
          icon: const Icon(Icons.construction), label: const Text('OPEN FIELD TOOLS')),
        _Notice(
          text: radio.isReady
              ? 'Verified Meshtastic session ready. Live NodeDB updates will appear above.'
              : 'Scan, then tap CONNECT on a radio. Bastion verifies the Meshtastic service, performs the PhoneAPI handshake, and synchronizes NodeDB before marking the session ready.',
          icon: radio.isReady ? Icons.verified_outlined : Icons.info_outline),
      ],
    ),
  );
}

class _ChatsPage extends StatefulWidget {
  const _ChatsPage({
    required this.radio,
    required this.botMode,
    required this.awayReply,
    required this.onBotModeChanged,
    required this.onAwayReplyChanged,
  });
  final MeshtasticRadioCoordinator radio;
  final bool botMode;
  final String awayReply;
  final ValueChanged<bool> onBotModeChanged;
  final ValueChanged<String> onAwayReplyChanged;

  @override
  State<_ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<_ChatsPage> {
  late final TextEditingController reply =
      TextEditingController(text: widget.awayReply);
  final composer = TextEditingController();
  int destination = 0xffffffff;

  @override
  void dispose() {
    reply.dispose();
    composer.dispose();
    super.dispose();
  }

  Future<void> _send([String? quickText]) async {
    final text = (quickText ?? composer.text).trim();
    if (text.isEmpty) return;
    try {
      await widget.radio.sendText(text: text, destination: destination);
      if (quickText == null) composer.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message not sent: $error')),
        );
      }
    }
  }

  String _nodeName(int nodeNum) {
    for (final node in widget.radio.nodes) {
      if (node.num == nodeNum) return node.displayName;
    }
    return '!\${nodeNum.toRadixString(16).padLeft(8, '0')}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.radio,
    builder: (context, _) {
      final messages = widget.radio.messages;
      final connected = widget.radio.isReady;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(
            icon: Icons.forum_outlined,
            title: 'COMMS',
            detail: connected
                ? 'Live Meshtastic messaging is ready.'
                : 'Connect a radio to send. Queued messages send automatically when READY.',
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Stat(
              label: 'LINK',
              value: connected ? 'READY' : 'OFFLINE',
            )),
            const SizedBox(width: 10),
            Expanded(child: _Stat(
              label: 'MESSAGES',
              value: messages.length.toString(),
            )),
            const SizedBox(width: 10),
            Expanded(child: _Stat(
              label: 'QUEUED',
              value: widget.radio.pendingMessageCount.toString(),
            )),
          ]),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DESTINATION',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: destination,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cell_tower),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 0xffffffff,
                    child: Text('Channel 0 • Broadcast'),
                  ),
                  for (final node in widget.radio.nodes)
                    DropdownMenuItem(
                      value: node.num,
                      child: Text('DM • \${node.displayName}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => destination = value);
                },
              ),
            ]),
          )),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              TextField(
                controller: composer,
                maxLength: 228,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: destination == 0xffffffff
                      ? 'Message Channel 0'
                      : 'Message \${_nodeName(destination)}',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _send(),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: connected ? _send : null,
                  icon: const Icon(Icons.send),
                  label: const Text('SEND'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (final quick in const [
                  'Copy',
                  'On my way',
                  'Need assistance',
                  'What is your position?',
                ])
                  ActionChip(
                    label: Text(quick),
                    onPressed: connected ? () => _send(quick) : null,
                  ),
              ]),
            ]),
          )),
          if (messages.isEmpty)
            const _EmptyState(
              icon: Icons.mark_chat_unread_outlined,
              title: 'No mesh messages yet',
              detail: 'Incoming Channel 0 and direct messages will appear here after a radio is connected.',
            )
          else ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text('MESSAGE TIMELINE',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
            ),
            for (final message in messages.reversed.take(50))
              Card(child: ListTile(
                leading: CircleAvatar(
                  child: Icon(message.direction == BastionMessageDirection.outgoing
                      ? Icons.north_east : Icons.south_west),
                ),
                title: Text(message.text),
                subtitle: Text(
                  message.direction == BastionMessageDirection.outgoing
                      ? (message.isBroadcast
                          ? 'You → Channel \${message.channel}'
                          : 'You → \${_nodeName(message.to)}')
                      : (message.isBroadcast
                          ? '\${_nodeName(message.from)} → Channel \${message.channel}'
                          : '\${_nodeName(message.from)} → You'),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_deliveryIcon(message.deliveryState), size: 18),
                    const SizedBox(height: 3),
                    Text(_deliveryLabel(message.deliveryState),
                      style: const TextStyle(fontSize: 9)),
                  ],
                ),
              )),
          ],
          const SizedBox(height: 10),
          Card(child: SwitchListTile(
            secondary: const Icon(Icons.smart_toy_outlined,
              color: BastionMeshtasticApp.cyan),
            title: const Text('BOT MODE',
              style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(widget.botMode
                ? 'Armed locally — command engine is next'
                : 'Automatic replies are off'),
            value: widget.botMode,
            onChanged: widget.onBotModeChanged,
          )),
          Card(child: ExpansionTile(
            leading: const Icon(Icons.tune, color: BastionMeshtasticApp.cyan),
            title: const Text('BOT RESPONSE',
              style: TextStyle(fontWeight: FontWeight.bold)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              TextField(
                controller: reply,
                maxLines: 3,
                maxLength: 160,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Message to send while Bot Mode is active',
                ),
                onChanged: widget.onAwayReplyChanged,
              ),
            ],
          )),
        ],
      );
    },
  );
}

IconData _deliveryIcon(BastionDeliveryState state) => switch (state) {
  BastionDeliveryState.received => Icons.call_received,
  BastionDeliveryState.queued => Icons.schedule,
  BastionDeliveryState.sent => Icons.check,
  BastionDeliveryState.failed => Icons.error_outline,
};

String _deliveryLabel(BastionDeliveryState state) => switch (state) {
  BastionDeliveryState.received => 'RX',
  BastionDeliveryState.queued => 'QUEUED',
  BastionDeliveryState.sent => 'SENT',
  BastionDeliveryState.failed => 'FAILED',
};

class _MapPage extends StatelessWidget {
  const _MapPage();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const _Header(icon: Icons.map_outlined, title: 'TACTICAL MAP',
        detail: 'A field view for mesh positions and coverage. Position pins require node position packets from a connected radio.'),
      const SizedBox(height: 14),
      Container(
        height: 280,
        decoration: BoxDecoration(color: BastionMeshtasticApp.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: BastionMeshtasticApp.cyan.withValues(alpha: .25))),
        child: const Stack(children: [
          Center(child: Icon(Icons.terrain, size: 110, color: Colors.white10)),
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.location_off_outlined, size: 42, color: BastionMeshtasticApp.cyan),
            SizedBox(height: 10),
            Text('WAITING FOR POSITION DATA', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text('Connect a Meshtastic radio to populate node pins.',
              style: TextStyle(color: Colors.white60)),
          ])),
        ]),
      ),
      const SizedBox(height: 12),
      const Row(children: [
        Expanded(child: _Stat(label: 'PINS', value: '0')), SizedBox(width: 10),
        Expanded(child: _Stat(label: 'TRACKS', value: '0')), SizedBox(width: 10),
        Expanded(child: _Stat(label: 'COVERAGE', value: '—')),
      ]),
    ],
  );
}

class _ToolsPage extends StatefulWidget {
  const _ToolsPage({required this.discovery});
  final MeshtasticBleDiscovery discovery;
  @override
  State<_ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<_ToolsPage> {
  final battery = TextEditingController(text: '3000');
  final draw = TextEditingController(text: '100');
  double? runtime;
  final checked = <String>{};
  static const checklist = [
    'Radio charged', 'Antenna attached', 'Region configured',
    'Primary channel verified', 'GPS / position policy checked',
  ];

  @override
  void dispose() { battery.dispose(); draw.dispose(); super.dispose(); }

  void calculate() {
    final mah = double.tryParse(battery.text);
    final ma = double.tryParse(draw.text);
    setState(() => runtime = mah != null && ma != null && ma > 0 ? mah / ma : null);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const _Header(icon: Icons.construction, title: 'FIELD TOOLS',
        detail: 'Practical utilities you can use before and during a deployment.'),
      const SizedBox(height: 14),
      Card(child: ExpansionTile(
        leading: const Icon(Icons.battery_charging_full, color: BastionMeshtasticApp.cyan),
        title: const Text('BATTERY RUNTIME', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Estimate runtime from capacity and average current'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(children: [
            Expanded(child: TextField(controller: battery,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Battery (mAh)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: draw,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Avg draw (mA)'))),
          ]),
          const SizedBox(height: 12),
          FilledButton(onPressed: calculate, child: const Text('CALCULATE')),
          if (runtime != null)
            Padding(padding: const EdgeInsets.only(top: 12),
              child: Text('Estimated runtime: ${runtime!.toStringAsFixed(1)} hours',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: BastionMeshtasticApp.cyan))),
        ],
      )),
      const Card(child: ExpansionTile(
        leading: Icon(Icons.signal_cellular_alt, color: BastionMeshtasticApp.cyan),
        title: Text('RSSI FIELD REFERENCE', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Quick Bluetooth signal-strength guide'),
        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _ReferenceRow(value: '−50 dBm', label: 'Excellent / very close'),
          _ReferenceRow(value: '−60 dBm', label: 'Strong'),
          _ReferenceRow(value: '−70 dBm', label: 'Usable'),
          _ReferenceRow(value: '−80 dBm', label: 'Weak'),
          _ReferenceRow(value: '≤ −90', label: 'Very weak / unstable'),
        ],
      )),
      Card(child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.checklist, color: BastionMeshtasticApp.cyan),
        title: const Text('DEPLOYMENT CHECKLIST', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${checked.length}/${checklist.length} ready'),
        children: [
          for (final item in checklist)
            CheckboxListTile(
              dense: true, title: Text(item), value: checked.contains(item),
              onChanged: (value) => setState(() {
                value == true ? checked.add(item) : checked.remove(item);
              }),
            ),
        ],
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.bluetooth_searching, color: BastionMeshtasticApp.cyan),
        title: const Text('RADIO SCANNER', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${widget.discovery.results.length} BLE devices currently discovered'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.discovery.scanning ? null : widget.discovery.scan,
      )),
      const Card(child: ListTile(enabled: false, leading: Icon(Icons.route),
        title: Text('TRACEROUTE'), subtitle: Text('Unlocks after verified radio connection'))),
      const Card(child: ListTile(enabled: false, leading: Icon(Icons.monitor_heart_outlined),
        title: Text('LIVE TELEMETRY'), subtitle: Text('Unlocks after verified radio connection'))),
    ],
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.lowPowerMode, required this.onLowPowerChanged});
  final bool lowPowerMode;
  final ValueChanged<bool> onLowPowerChanged;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const _Header(icon: Icons.tune, title: 'SETTINGS',
        detail: 'Field behavior, connection preferences and build information.'),
      const SizedBox(height: 14),
      Card(child: SwitchListTile(
        secondary: const Icon(Icons.battery_saver_outlined),
        title: const Text('Low-power field mode'),
        subtitle: const Text('Reduce optional background activity'),
        value: lowPowerMode, onChanged: onLowPowerChanged)),
      const Card(child: ListTile(
        leading: Icon(Icons.bluetooth), title: Text('Preferred transport'),
        subtitle: Text('Bluetooth LE'), trailing: Text('BLE'))),
      const Card(child: ListTile(
        leading: Icon(Icons.security_outlined), title: Text('Safety mode'),
        subtitle: Text('No unverified device is treated as a mesh node'),
        trailing: Icon(Icons.verified_user_outlined, color: BastionMeshtasticApp.cyan))),
      const Card(child: ListTile(
        leading: Icon(Icons.info_outline), title: Text('Bastion Meshtastic'),
        subtitle: Text('Development build • Independent Meshtastic companion'))),
      const _Notice(
        text: 'Bastion is an independent companion project and is not an official Meshtastic application. Do not rely on this development build for emergency communication.',
        icon: Icons.shield_outlined),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: BastionMeshtasticApp.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BastionMeshtasticApp.cyan.withValues(alpha: .4))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: BastionMeshtasticApp.cyan, size: 30),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
          color: BastionMeshtasticApp.cyan, letterSpacing: .8)),
        const SizedBox(height: 6),
        Text(detail, style: const TextStyle(height: 1.4, color: Colors.white70)),
      ])),
    ]),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
    decoration: BoxDecoration(color: BastionMeshtasticApp.panel,
      borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w900,
        fontSize: 17, color: BastionMeshtasticApp.cyan)),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: .6)),
    ]),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, size: 20, color: Colors.white54), const SizedBox(width: 10),
        Expanded(child: Text(text,
          style: const TextStyle(fontSize: 12, color: Colors.white60))),
      ]),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(children: [
        Icon(icon, size: 38, color: Colors.white30), const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(detail, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, height: 1.4)),
      ]),
    ),
  );
}

class _ReferenceRow extends StatelessWidget {
  const _ReferenceRow({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      SizedBox(width: 80, child: Text(value,
        style: const TextStyle(fontWeight: FontWeight.bold,
          color: BastionMeshtasticApp.cyan))),
      Expanded(child: Text(label)),
    ]),
  );
}

String _rssiLabel(int rssi) {
  if (rssi >= -60) return 'Strong Bluetooth signal';
  if (rssi >= -75) return 'Usable Bluetooth signal';
  if (rssi >= -90) return 'Weak Bluetooth signal';
  return 'Very weak Bluetooth signal';
}


String _connectionLabel(MeshtasticConnectionState state) => switch (state) {
  MeshtasticConnectionState.disconnected => 'OFFLINE',
  MeshtasticConnectionState.discovering => 'SCANNING',
  MeshtasticConnectionState.connecting => 'CONNECTING',
  MeshtasticConnectionState.connected => 'CONNECTED',
  MeshtasticConnectionState.synchronizing => 'SYNCING',
  MeshtasticConnectionState.ready => 'READY',
  MeshtasticConnectionState.error => 'ERROR',
};
