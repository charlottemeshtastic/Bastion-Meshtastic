import 'dart:convert';
import 'package:flutter/material.dart';
import '../../generated/meshtastic/channel.pbenum.dart';
import '../../models/chat_message.dart';
import '../../services/meshtastic/radio_session.dart';
import '../../services/messaging/chat_history.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key, required this.session, required this.history});
  final RadioSession session;
  final ChatHistory history;
  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _text = TextEditingController();
  int? _radio;
  String? _conversation;
  bool _sending = false;
  String? _error;
  @override
  void dispose() { _text.dispose(); super.dispose(); }

  String _nodeLabel(int number) {
    for (final node in widget.session.nodes) {
      if (node.number == number) {
        return node.displayName;
      }
    }
    return '!${number.toRadixString(16).padLeft(8, '0')}';
  }

  Future<void> _send(int channel, int destination) async {
    final text = _text.text;
    setState(() { _sending = true; _error = null; });
    try {
      await widget.session.sendText(text, channel: channel, destination: destination);
      if (mounted && _text.text == text) {
        _text.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Send not confirmed: ${e.toString()}. Check history before retrying.');
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.session, widget.history]),
    builder: (context, _) {
      final session = widget.session;
      final history = widget.history;
      final radios = <int>{if (session.localNode != null) session.localNode!,
        ...history.messages.map((m) => m.radio)};
      final radio = radios.contains(_radio) ? _radio :
        session.localNode ?? (radios.isEmpty ? null : radios.first);
      final messages = history.messages.where((m) => m.radio == radio).toList();
      final live = session.status == RadioStatus.ready && radio == session.localNode;
      final enabled = session.channels.values.where((c) => c.role != Channel_Role.DISABLED).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      final options = <String, String>{};
      if (live) {
        for (final channel in enabled) {
          options['c:${channel.index}'] = channel.hasSettings() && channel.settings.name.isNotEmpty
            ? 'Channel · ${channel.settings.name}' : 'Channel ${channel.index}';
        }
        for (final node in session.nodes.where((n) => n.number != radio)) {
          options['d:${node.number}'] = 'Direct · ${node.displayName}';
        }
      }
      for (final message in messages) {
        final key = message.isDirect ? 'd:${message.peer}' : 'c:${message.channel}';
        options.putIfAbsent(key, () => message.isDirect
          ? 'Direct · ${_nodeLabel(message.peer)}' : 'Channel ${message.channel} · saved');
      }
      final selected = options.containsKey(_conversation) ? _conversation :
        (options.isEmpty ? null : options.keys.first);
      final direct = selected?.startsWith('d:') ?? false;
      final number = selected == null ? null : int.parse(selected.substring(2));
      var channel = direct ? (enabled.isEmpty ? null : enabled.first.index) : number;
      if (direct) {
        for (final item in enabled) {
          if (item.role == Channel_Role.PRIMARY) {
            channel = item.index;
            break;
          }
        }
      }
      final canSend = live && !history.loading && history.error == null &&
        !_sending && channel != null && enabled.any((c) => c.index == channel);
      final visible = messages.where((m) => direct
        ? m.isDirect && m.peer == number
        : !m.isDirect && m.channel == number).toList();
      final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
      return Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MESH CHATS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(live ? 'Connected · channel and direct messages' : 'Offline · saved history'),
            if (history.loading) const LinearProgressIndicator(),
            if (history.error != null) Text(history.error!,
              style: const TextStyle(color: Colors.orangeAccent)),
            if (radios.isNotEmpty && !keyboardOpen)
              DropdownButton<int>(isExpanded: true, value: radio,
                items: radios.map((r) => DropdownMenuItem(value: r,
                  child: Text('Radio ${_nodeLabel(r)}'))).toList(),
                onChanged: _sending ? null : (value) => setState(() {
                  _radio = value; _conversation = null;
                })),
            if (options.isNotEmpty && !keyboardOpen)
              DropdownButton<String>(isExpanded: true, value: selected,
                items: options.entries.map((entry) => DropdownMenuItem(
                  value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: _sending ? null : (value) => setState(() => _conversation = value)),
            if (keyboardOpen && selected != null) Text(options[selected]!),
            if (direct && !keyboardOpen) const Text('Direct destination. Encryption follows your radio configuration.',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
          ])),
        Expanded(child: visible.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(20), child:
              Text('No messages yet. Connect a radio in NODES, then choose a channel or node.')))
          : ListView.builder(reverse: true, padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: visible.length, itemBuilder: (context, index) {
                final message = visible[visible.length - 1 - index];
                return Card(child: Padding(padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(message.outgoing ? 'You' : _nodeLabel(message.from),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    SelectableText(message.text),
                    const SizedBox(height: 6),
                    Text('${message.time.toLocal()} · ${message.statusLabel}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    if (message.detail != null) Text(message.detail!,
                      style: const TextStyle(fontSize: 11, color: Colors.orangeAccent)),
                  ])));
              })),
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
          TextField(controller: _text, enabled: !_sending, maxLines: 3, minLines: 1,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Message',
              helperText: '${utf8.encode(_text.text.trim()).length}/233 bytes · no automatic retries')),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: canSend && _text.text.trim().isNotEmpty
            ? () => _send(channel!, direct ? number! : ChatMessage.broadcast) : null,
            icon: const Icon(Icons.send_outlined),
            label: Text(_sending ? 'SENDING…' : 'SEND MESSAGE')),
        ])),
      ]);
    });
}
