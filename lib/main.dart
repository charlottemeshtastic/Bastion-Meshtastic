import 'package:flutter/material.dart';
import 'map_page.dart';
import 'node_detail_page.dart';
import 'radio_settings_page.dart';
import 'services/bastion_tile_cache.dart';
import 'traceroute_page.dart';
import 'services/meshtastic_ble_discovery.dart';
import 'services/meshtastic_connection_controller.dart';
import 'services/meshtastic_messaging_service.dart';
import 'services/meshtastic_radio_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BastionTileCache.initialize();
  runApp(const BastionApp());
}

class BastionApp extends StatelessWidget {
  const BastionApp({super.key});
  static const signal = Color(0xFFC7A24A);
  static const panel = Color(0xFF151713);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bastion',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D0F0C),
      colorScheme: ColorScheme.fromSeed(seedColor: signal, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0D0F0C)),
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
          color: BastionApp.signal, letterSpacing: 2)),
        Text('FIELD MESH', style: TextStyle(fontSize: 10, letterSpacing: 1.4)),
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
        onBotModeChanged: (value) {
          setState(() => botMode = value);
          radio.configureBot(enabled: value, reply: awayReply);
        },
        onAwayReplyChanged: (value) {
          setState(() => awayReply = value);
          radio.configureBot(enabled: botMode, reply: value);
        },
      ),
      MapPage(radio: radio),
      _ToolsPage(discovery: ble, radio: radio),
      _SettingsPage(
        radio: radio,
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
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${item.id}\n${item.advertisesMeshtastic ? 'Meshtastic service advertised' : _rssiLabel(item.rssi)}',
              ),
              isThreeLine: true,
              trailing: (radio.isReady || radio.isReconnecting) &&
                      radio.connection.deviceName == item.name
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
                      child: const Text('CONNECT', maxLines: 1, softWrap: false),
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => NodeDetailPage(radio: radio, nodeNum: node.num),
              )),
            )),
        ],
        if (radio.isReady) ...[
          const SizedBox(height: 14),
          const Text('MESH HEALTH • LIVE SESSION',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Stat(label: 'KNOWN NODES',
              value: '${radio.nodes.length}')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: 'MESSAGES',
              value: '${radio.messages.length}')),
            const SizedBox(width: 10),
            Expanded(child: _Stat(label: 'PENDING',
              value: '${radio.pendingMessageCount}')),
          ]),
          const SizedBox(height: 10),
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('RECEIVE SIGNAL • TEXT PACKETS',
                style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Received: ${radio.receivedTextPackets} • Latest SNR: '
                '${radio.latestSnr == null ? 'Waiting for packet' : '${radio.latestSnr!.toStringAsFixed(1)} dB'}'),
              const SizedBox(height: 10),
              if (radio.snrHistory.isNotEmpty)
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final snr in radio.snrHistory.reversed.take(20).toList().reversed)
                    Tooltip(message: '${snr.toStringAsFixed(1)} dB',
                      child: Container(
                        width: 10,
                        height: 12 + (snr + 20).clamp(0, 40).toDouble(),
                        decoration: BoxDecoration(
                          color: BastionApp.signal,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )),
                ])
              else
                const Text('Send a message from another node to start the SNR history.'),
            ]),
          )),
          const SizedBox(height: 6),
          const _Notice(
            text: 'SNR values come from received text packets only. '
              'RSSI and delivery-rate monitoring are not available yet.',
            icon: Icons.monitor_heart_outlined,
          ),
        ],
        if (radio.nodeDex.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('NODEDEX • SAVED ENCOUNTERS',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(height: 6),
          for (final record in radio.nodeDex)
            Card(child: ListTile(
              leading: Icon(record.favorite ? Icons.star : Icons.person_pin_circle_outlined,
                color: record.favorite ? BastionApp.signal : null),
              title: Text(record.displayName),
              subtitle: Text('Encounters: ${record.encounters} • Last seen: ${record.lastSeen.toLocal()}'
                '\n${record.note.isEmpty ? 'Tap to add field notes' : record.note}'),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: record.favorite ? 'Remove favorite' : 'Favorite node',
                icon: Icon(record.favorite ? Icons.star : Icons.star_border),
                onPressed: () => radio.setNodeFavorite(record.num, !record.favorite),
              ),
              onTap: () async {
                final editor = TextEditingController(text: record.note);
                final note = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text('Field notes • ${record.displayName}'),
                    content: TextField(
                      controller: editor,
                      autofocus: true,
                      maxLines: 3,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        hintText: 'Location, antenna, observations…',
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('CANCEL')),
                      FilledButton(onPressed: () => Navigator.pop(dialogContext, editor.text),
                        child: const Text('SAVE')),
                    ],
                  ),
                );
                if (note != null) await radio.setNodeNote(record.num, note);
              },
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
    return '!${nodeNum.toRadixString(16).padLeft(8, '0')}';
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
                : 'Messages can be queued offline and send automatically when the radio is connected.',
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Stat(
              label: 'LINK',
              value: connected ? 'CONNECTED' : 'OFFLINE',
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
                      child: Text('DM • ${node.displayName}'),
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
                      : 'Message ${_nodeName(destination)}',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _send(),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _send,
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
                    onPressed: () => _send(quick),
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
                          ? 'You → Channel ${message.channel}'
                          : 'You → ${_nodeName(message.to)}')
                      : (message.isBroadcast
                          ? '${_nodeName(message.from)} → Channel ${message.channel}'
                          : '${_nodeName(message.from)} → You'),
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
              color: BastionApp.signal),
            title: const Text('BOT MODE',
              style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(widget.botMode
                ? 'ACTIVE • DM auto-reply + !help / !status • 30s loop guard'
                : 'Automatic replies are off'),
            value: widget.botMode,
            onChanged: widget.onBotModeChanged,
          )),
          Card(child: ExpansionTile(
            leading: const Icon(Icons.tune, color: BastionApp.signal),
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
  BastionDeliveryState.delivered => Icons.done_all,
  BastionDeliveryState.failed => Icons.error_outline,
};

String _deliveryLabel(BastionDeliveryState state) => switch (state) {
  BastionDeliveryState.received => 'RX',
  BastionDeliveryState.queued => 'QUEUED',
  BastionDeliveryState.sent => 'SENT',
  BastionDeliveryState.delivered => 'DELIVERED',
  BastionDeliveryState.failed => 'FAILED',
};

class _ToolsPage extends StatefulWidget {
  const _ToolsPage({required this.discovery, required this.radio});
  final MeshtasticBleDiscovery discovery;
  final MeshtasticRadioCoordinator radio;
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
        leading: const Icon(Icons.battery_charging_full, color: BastionApp.signal),
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
                  color: BastionApp.signal))),
        ],
      )),
      const Card(child: ExpansionTile(
        leading: Icon(Icons.signal_cellular_alt, color: BastionApp.signal),
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
        leading: const Icon(Icons.checklist, color: BastionApp.signal),
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
        leading: const Icon(Icons.bluetooth_searching, color: BastionApp.signal),
        title: const Text('RADIO SCANNER', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${widget.discovery.results.length} BLE devices currently discovered'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.discovery.scanning ? null : widget.discovery.scan,
      )),
      AnimatedBuilder(
        animation: widget.radio,
        builder: (context, _) => Card(child: ListTile(
          enabled: widget.radio.isReady,
          leading: const Icon(Icons.route),
          title: const Text('TRACEROUTE', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(widget.radio.isReady
            ? 'Show the relay path to a node and back'
            : 'Connect to a radio to trace routes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => TraceroutePage(radio: widget.radio),
          )),
        )),
      ),
      AnimatedBuilder(
        animation: widget.radio,
        builder: (context, _) {
          final readings = widget.radio.deviceTelemetry.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          return Card(child: ExpansionTile(
            leading: const Icon(Icons.monitor_heart_outlined, color: BastionApp.signal),
            title: const Text('LIVE TELEMETRY',
              style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(widget.radio.isReady
              ? '${readings.length} nodes reporting device metrics'
              : 'Connect to a radio to receive telemetry'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (readings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No device telemetry received yet. Metrics appear when nodes transmit them.'),
                ),
              for (final entry in readings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Node !${entry.key.toRadixString(16).padLeft(8, '0')}'),
                  subtitle: Text([
                    if (entry.value.batteryLevel != null)
                      'Battery ${entry.value.batteryLevel}%',
                    if (entry.value.voltage != null)
                      'Voltage ${entry.value.voltage!.toStringAsFixed(2)} V',
                    if (entry.value.channelUtilization != null)
                      'Channel ${entry.value.channelUtilization!.toStringAsFixed(1)}%',
                    if (entry.value.airUtilTx != null)
                      'TX airtime ${entry.value.airUtilTx!.toStringAsFixed(1)}%',
                  ].join(' · ')),
                ),
            ],
          ));
        },
      ),
    ],
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.radio, required this.lowPowerMode, required this.onLowPowerChanged});
  final MeshtasticRadioCoordinator radio;
  final bool lowPowerMode;
  final ValueChanged<bool> onLowPowerChanged;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const _Header(icon: Icons.tune, title: 'SETTINGS',
        detail: 'Field behavior, connection preferences and build information.'),
      const SizedBox(height: 14),
      AnimatedBuilder(
        animation: radio,
        builder: (context, _) => Card(child: ExpansionTile(
          initiallyExpanded: true,
          leading: const Icon(Icons.settings_input_antenna, color: BastionApp.signal),
          title: const Text('RADIO CONFIGURATION',
            style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(radio.canAdminister
            ? 'Radio connected • settings can be changed'
            : 'Connect to a radio to view and change its settings'),
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Node identity'),
              subtitle: Text(radio.localNode == null
                ? 'Waiting for this radio\'s node information'
                : 'Long: ${radio.localNode!.longName ?? 'Not reported'}\n'
                  'Short: ${radio.localNode!.shortName ?? 'Not reported'}\n'
                  'ID: ${radio.localNode!.id ?? 'Not reported'}'),
              isThreeLine: true,
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Change radio settings'),
              subtitle: const Text('Owner, LoRa, channels, device role and position'),
              enabled: radio.canAdminister,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => RadioSettingsPage(radio: radio),
              )),
            ),
            ListTile(title: const Text('Device & LoRa'),
              subtitle: Text(radio.loraSettings.isEmpty
                ? '${radio.radioConfigCount} configuration messages • LoRa values unavailable'
                : radio.loraSettings.join('\n'))),
            ListTile(
              title: const Text('Channels'),
              subtitle: Text(radio.channelSettings.isEmpty
                ? '${radio.channelConfigCount} channel messages • details unavailable'
                : radio.channelSettings.join('\n')),
            ),
            ListTile(title: const Text('Modules'),
              subtitle: Text('${radio.moduleConfigCount} module messages received • editing coming soon')),
          ],
        )),
      ),
      AnimatedBuilder(
        animation: radio,
        builder: (context, _) {
          final sent = radio.lastPhonePositionSent;
          final status = radio.locationShareProblem ??
              (!radio.sharePhoneLocation
                  ? 'Off. Your phone location is never sent.'
                  : !radio.isReady
                      ? 'On. Starts when a radio is connected.'
                      : sent == null
                          ? 'On. Waiting for a GPS fix.'
                          : 'On. Last sent ${sent.toLocal().toString().substring(11, 16)}.');
          return Card(child: SwitchListTile(
            secondary: const Icon(Icons.share_location),
            title: const Text('Share phone location with mesh'),
            subtitle: Text('$status\nThe radio broadcasts it when it has no GPS of its own. '
                'Updates every 5 min, or sooner when you move.'),
            isThreeLine: true,
            value: radio.sharePhoneLocation,
            onChanged: (value) => radio.setSharePhoneLocation(value),
          ));
        },
      ),
      const _MapCacheCard(),
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
        trailing: Icon(Icons.verified_user_outlined, color: BastionApp.signal))),
      const Card(child: ListTile(
        leading: Icon(Icons.info_outline), title: Text('Bastion'),
        subtitle: Text('Development build • Independent mesh companion'))),
      const Card(child: ListTile(
        leading: Icon(Icons.gavel_outlined),
        title: Text('Trademark & compatibility'),
        subtitle: Text(
          'Compatible with Meshtastic® firmware. Meshtastic® is a registered trademark of Meshtastic LLC. Meshtastic software components are released under various licenses, see GitHub for details. No warranty is provided - use at your own risk.\\n\\nBastion is independently developed and is not affiliated with, sponsored by, or endorsed by Meshtastic LLC.',
        ),
      )),
      const _Notice(
        text: 'Bastion is an independent project compatible with Meshtastic® firmware. It is not affiliated with, sponsored by, or endorsed by Meshtastic LLC. Do not rely on this development build as a sole method of emergency communication.',
        icon: Icons.shield_outlined),
    ],
  );
}

/// Safe channel editor preview. No channel write is attempted until authenticated
/// admin responses and verified radio readback are implemented.
class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: BastionApp.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: BastionApp.signal.withValues(alpha: .4))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: BastionApp.signal, size: 30),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
          color: BastionApp.signal, letterSpacing: .8)),
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
    decoration: BoxDecoration(color: BastionApp.panel,
      borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1,
        softWrap: false, style: const TextStyle(fontWeight: FontWeight.w900,
        fontSize: 17, color: BastionApp.signal))),
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
          color: BastionApp.signal))),
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
  MeshtasticConnectionState.ready => 'CONNECTED',
  MeshtasticConnectionState.error => 'ERROR',
};

class _MapCacheCard extends StatefulWidget {
  const _MapCacheCard();

  @override
  State<_MapCacheCard> createState() => _MapCacheCardState();
}

class _MapCacheCardState extends State<_MapCacheCard> {
  late Future<int?> _size = BastionTileCache.sizeBytes();

  @override
  Widget build(BuildContext context) => Card(child: FutureBuilder<int?>(
    future: _size,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      return ListTile(
        leading: const Icon(Icons.offline_pin_outlined),
        title: const Text('Offline map tiles'),
        subtitle: Text('${bytes == null ? 'Size unknown' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB saved'}'
          '\nMap areas you view online stay available offline for a year (up to 500 MB).'),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: bytes == null || bytes == 0 ? null : () async {
            await BastionTileCache.clear();
            if (mounted) setState(() => _size = BastionTileCache.sizeBytes());
          },
          child: const Text('Clear'),
        ),
      );
    },
  ));
}
