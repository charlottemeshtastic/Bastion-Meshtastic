import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'generated/meshtastic/apponly.pb.dart';
import 'qr_scan_page.dart';
import 'services/meshtastic_channel_url.dart';
import 'services/meshtastic_radio_coordinator.dart';

/// Shows the radio's channels as a Meshtastic QR code and link.
class ChannelSharePage extends StatefulWidget {
  const ChannelSharePage({super.key, required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  State<ChannelSharePage> createState() => _ChannelSharePageState();
}

class _ChannelSharePageState extends State<ChannelSharePage> {
  late Future<ChannelSet> _channels = widget.radio.readChannelSet();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Share channels')),
        body: FutureBuilder<ChannelSet>(
          future: _channels,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text('Could not read channels: ${snapshot.error}'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _channels = widget.radio.readChannelSet()),
                    child: const Text('Retry'),
                  ),
                ),
              ]);
            }
            final set = snapshot.data;
            if (set == null) return const Center(child: CircularProgressIndicator());
            final link = MeshtasticChannelUrl.encode(set);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(data: link, size: 260),
                  ),
                ),
                const SizedBox(height: 16),
                for (final (i, s) in set.settings.indexed)
                  Text('${i == 0 ? 'Primary' : 'Secondary'}: ${s.name.isEmpty ? '(default name)' : s.name}'),
                const SizedBox(height: 12),
                SelectableText(link, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy link'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: link));
                      messenger.showSnackBar(const SnackBar(content: Text('Channel link copied.')));
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This code contains your channel encryption keys. Anyone who '
                  'scans it can read and send on these channels.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            );
          },
        ),
      );
}

/// Pastes a Meshtastic channel link and applies it to the radio.
class ChannelImportPage extends StatefulWidget {
  const ChannelImportPage({super.key, required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  State<ChannelImportPage> createState() => _ChannelImportPageState();
}

class _ChannelImportPageState extends State<ChannelImportPage> {
  final _link = TextEditingController();
  ChannelSet? _set;
  String? _error;
  bool _replace = false;
  bool _saving = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _parse(String text) {
    setState(() {
      if (text.trim().isEmpty) {
        _set = null;
        _error = null;
        return;
      }
      try {
        _set = MeshtasticChannelUrl.decode(text);
        _replace = !MeshtasticChannelUrl.isAddLink(text);
        _error = null;
      } on FormatException catch (e) {
        _set = null;
        _error = e.message;
      }
    });
  }

  Future<void> _apply() async {
    final set = _set;
    if (set == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_replace ? 'Replace all channels?' : 'Add channels?'),
        content: Text(_replace
            ? 'All 8 channel slots${set.hasLoraConfig() ? ' and the LoRa settings' : ''} '
                'will be overwritten. You will lose access to current channels '
                'unless you have their link. The radio will reboot.'
            : 'New channels from the link go into free slots. Existing channels '
                'and LoRa settings stay the same.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final count = await widget.radio.applyChannelSet(set, replace: _replace);
      messenger.showSnackBar(SnackBar(content: Text(count == 0
          ? 'All channels from the link are already on the radio.'
          : '$count channel${count == 1 ? '' : 's'} written to radio.')));
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final set = _set;
    return Scaffold(
      appBar: AppBar(title: const Text('Import channels')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan channel QR code'),
            onPressed: () async {
              final scanned = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const QrScanPage(title: 'Scan channel QR')),
              );
              if (scanned == null || !mounted) return;
              _link.text = scanned;
              _parse(scanned);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _link,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Meshtastic channel link',
              hintText: MeshtasticChannelUrl.prefix,
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text ?? '';
                  _link.text = text;
                  _parse(text);
                },
              ),
            ),
            onChanged: _parse,
          ),
          if (set != null) ...[
            const SizedBox(height: 12),
            for (final (i, s) in set.settings.indexed)
              Text('${i + 1}. ${s.name.isEmpty ? '(default name)' : s.name}'),
            if (set.hasLoraConfig())
              Text('LoRa: ${set.loraConfig.region.name}, '
                  '${set.loraConfig.usePreset ? set.loraConfig.modemPreset.name : 'custom modem'}'),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Add to radio')),
                ButtonSegment(value: true, label: Text('Replace all')),
              ],
              selected: {_replace},
              onSelectionChanged: (v) => setState(() => _replace = v.single),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving || !widget.radio.canAdminister ? null : _apply,
              child: _saving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Apply to radio'),
            ),
          ],
        ],
      ),
    );
  }
}
