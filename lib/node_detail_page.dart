import 'package:flutter/material.dart';

import 'services/bastion_chat_message.dart';
import 'services/bastion_geo.dart';
import 'services/bastion_nodedex.dart';
import 'services/meshtastic_node_database.dart';
import 'services/meshtastic_radio_coordinator.dart';
import 'traceroute_page.dart';

/// Everything known about one mesh node, with actions to reach it.
class NodeDetailPage extends StatefulWidget {
  const NodeDetailPage({super.key, required this.radio, required this.nodeNum});

  final MeshtasticRadioCoordinator radio;
  final int nodeNum;

  @override
  State<NodeDetailPage> createState() => _NodeDetailPageState();
}

class _NodeDetailPageState extends State<NodeDetailPage> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  MeshtasticRadioCoordinator get _radio => widget.radio;

  MeshtasticNode? get _node {
    for (final node in _radio.nodes) {
      if (node.num == widget.nodeNum) return node;
    }
    return null;
  }

  BastionNodeRecord? get _record {
    for (final record in _radio.nodeDex) {
      if (record.num == widget.nodeNum) return record;
    }
    return null;
  }

  String get _hexId => '!${widget.nodeNum.toRadixString(16).padLeft(8, '0')}';

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
    }
  }

  Future<void> _sendDirect() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _radio.sendText(text: text, destination: widget.nodeNum);
      _message.clear();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Send failed: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _editNote(BastionNodeRecord? record) async {
    final controller = TextEditingController(text: record?.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Field note'),
        content: TextField(controller: controller, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note != null) await _radio.setNodeNote(widget.nodeNum, note);
  }

  static String _ago(DateTime? time) {
    if (time == null) return 'unknown';
    final d = DateTime.now().difference(time);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _radio,
        builder: (context, _) {
          final node = _node;
          final record = _record;
          final telemetry = _radio.deviceTelemetry[widget.nodeNum];
          final local = _radio.localNode;
          final isSelf = widget.nodeNum == _radio.localNodeNum;
          final ready = _radio.isReady && !isSelf;
          final distance = node != null && node.hasPosition && local != null && local.hasPosition && !isSelf
              ? BastionGeo.distanceMeters(local.latitude!, local.longitude!, node.latitude!, node.longitude!)
              : null;
          final battery = node?.batteryLevel ?? telemetry?.batteryLevel;
          final directMessages = _radio.messages
              .where((m) =>
                  (m.direction == BastionMessageDirection.incoming && m.from == widget.nodeNum && !m.isBroadcast) ||
                  (m.direction == BastionMessageDirection.outgoing && m.to == widget.nodeNum))
              .toList();
          final recent = directMessages.length > 20
              ? directMessages.sublist(directMessages.length - 20)
              : directMessages;

          return Scaffold(
            appBar: AppBar(
              title: Text(node?.displayName ?? record?.displayName ?? _hexId),
              actions: [
                IconButton(
                  tooltip: (record?.favorite ?? false) ? 'Remove favorite' : 'Add favorite',
                  icon: Icon((record?.favorite ?? false) ? Icons.star : Icons.star_border),
                  onPressed: () => _radio.setNodeFavorite(widget.nodeNum, !(record?.favorite ?? false)),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Row('ID', node?.id ?? _hexId),
                        if (node?.shortName != null) _Row('Short name', node!.shortName!),
                        if (node?.hardwareModel != null) _Row('Hardware', 'Model ${node!.hardwareModel}'),
                        if (isSelf) const _Row('This radio', 'Yes'),
                        _Row('Last heard', _ago(node?.lastHeard ?? record?.lastSeen)),
                        if (node?.snr != null) _Row('SNR', '${node!.snr!.toStringAsFixed(1)} dB'),
                        if (node?.hopsAway != null)
                          _Row('Hops away', node!.hopsAway == 0 ? 'Direct' : '${node.hopsAway}'),
                        if (battery != null)
                          _Row('Battery', battery > 100 ? 'External power' : '$battery%'),
                        if (telemetry?.voltage != null)
                          _Row('Voltage', '${telemetry!.voltage!.toStringAsFixed(2)} V'),
                        if (telemetry?.channelUtilization != null)
                          _Row('Channel use', '${telemetry!.channelUtilization!.toStringAsFixed(1)}%'),
                        if (node != null && node.hasPosition) ...[
                          _Row('Position',
                              '${node.latitude!.toStringAsFixed(5)}, ${node.longitude!.toStringAsFixed(5)}'),
                          if (node.altitudeMeters != null) _Row('Altitude', '${node.altitudeMeters} m'),
                          _Row('Position age', _ago(node.positionTime)),
                        ],
                        if (distance != null)
                          _Row('Distance', distance < 1000
                              ? '${distance.round()} m'
                              : '${(distance / 1000).toStringAsFixed(1)} km'),
                        if (record != null) _Row('Encounters', '${record.encounters}'),
                      ],
                    ),
                  ),
                ),
                if (!isSelf) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.route),
                        label: const Text('Traceroute'),
                        onPressed: ready
                            ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => TraceroutePage(radio: _radio, initialTarget: widget.nodeNum),
                                ))
                            : null,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.my_location),
                        label: const Text('Request position'),
                        onPressed: ready
                            ? () => _run(() => _radio.requestPosition(widget.nodeNum),
                                'Position requested. It updates when the node replies.')
                            : null,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.battery_unknown),
                        label: const Text('Request telemetry'),
                        onPressed: ready
                            ? () => _run(() => _radio.requestTelemetry(widget.nodeNum),
                                'Telemetry requested. It updates when the node replies.')
                            : null,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: const Text('Field note'),
                    subtitle: Text((record?.note.isEmpty ?? true) ? 'Tap to add a note' : record!.note),
                    onTap: () => _editNote(record),
                  ),
                ),
                if (!isSelf) ...[
                  const SizedBox(height: 16),
                  const Text('DIRECT MESSAGES', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (recent.isEmpty)
                    const Text('No direct messages with this node yet.',
                        style: TextStyle(color: Colors.white60)),
                  for (final m in recent)
                    Align(
                      alignment: m.direction == BastionMessageDirection.outgoing
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(m.text),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _message,
                          enabled: _radio.isReady,
                          maxLength: 200,
                          decoration: const InputDecoration(hintText: 'Direct message'),
                          onSubmitted: (_) => _sendDirect(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Send',
                        icon: const Icon(Icons.send),
                        onPressed: _radio.isReady && !_sending ? _sendDirect : null,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white60))),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
