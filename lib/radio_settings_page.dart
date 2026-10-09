import 'dart:math';

import 'package:flutter/material.dart';
import 'package:protobuf/protobuf.dart';

import 'channel_share_page.dart';
import 'generated/meshtastic/admin.pb.dart';
import 'generated/meshtastic/channel.pb.dart';
import 'generated/meshtastic/config.pb.dart';
import 'generated/meshtastic/mesh.pb.dart' show User;
import 'services/bastion_channel_validation.dart';
import 'services/bastion_node_identity_validation.dart';
import 'services/meshtastic_radio_coordinator.dart';

/// Editable radio settings backed by the admin session.
///
/// Every editor loads the radio's current value, edits a copy, and writes it
/// back only after explicit confirmation. The radio may reboot after a write;
/// the coordinator reconnects automatically.
class RadioSettingsPage extends StatelessWidget {
  const RadioSettingsPage({super.key, required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Radio settings')),
        body: AnimatedBuilder(
          animation: radio,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!radio.canAdminister)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.link_off),
                    title: Text('Radio not ready'),
                    subtitle: Text('Connect to a radio and wait for READY to change settings.'),
                  ),
                ),
              _entry(context, Icons.person_outline, 'Owner',
                  'Long and short node names', () => _OwnerEditor(radio: radio)),
              _entry(context, Icons.settings_input_antenna, 'LoRa',
                  'Region, modem preset, hop limit, transmit', () => _LoraEditor(radio: radio)),
              _entry(context, Icons.forum_outlined, 'Channels',
                  'Names, roles and encryption keys', () => _ChannelListPage(radio: radio)),
              _entry(context, Icons.memory, 'Device',
                  'Device role and rebroadcast mode', () => _DeviceEditor(radio: radio)),
              _entry(context, Icons.my_location, 'Position',
                  'Broadcast interval, GPS mode, smart position', () => _PositionEditor(radio: radio)),
            ],
          ),
        ),
      );

  Widget _entry(BuildContext context, IconData icon, String title, String detail,
          Widget Function() page) =>
      Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(detail),
          trailing: const Icon(Icons.chevron_right),
          enabled: radio.canAdminister,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
        ),
      );
}

/// Shared load → edit → confirm → write flow for one protobuf message.
class _AdminEditor<T extends GeneratedMessage> extends StatefulWidget {
  const _AdminEditor({
    required this.title,
    required this.load,
    required this.save,
    required this.fields,
    this.validate,
    this.warning,
  });

  final String title;
  final Future<T> Function() load;
  final Future<void> Function(T draft) save;
  final List<Widget> Function(T draft, VoidCallback changed) fields;

  /// Returns an error that blocks saving, or null.
  final String? Function(T draft)? validate;

  /// Returns an extra warning shown in the confirmation dialog, or null.
  final String? Function(T original, T draft)? warning;

  @override
  State<_AdminEditor<T>> createState() => _AdminEditorState<T>();
}

class _AdminEditorState<T extends GeneratedMessage> extends State<_AdminEditor<T>> {
  T? _original;
  T? _draft;
  Object? _loadError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loadError = null;
      _original = null;
      _draft = null;
    });
    try {
      final value = await widget.load();
      if (!mounted) return;
      setState(() {
        _original = value;
        _draft = value.deepCopy();
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _save() async {
    final original = _original;
    final draft = _draft;
    if (original == null || draft == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final warning = widget.warning?.call(original, draft);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save ${widget.title.toLowerCase()}?'),
        content: Text([
          'This writes the change to the connected radio. '
              'The radio may reboot and reconnect.',
          ?warning,
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.save(draft);
      messenger.showSnackBar(SnackBar(content: Text('${widget.title} saved to radio.')));
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final error = draft == null ? null : widget.validate?.call(draft);
    final dirty = draft != null && draft != _original;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: dirty && error == null && !_saving ? _save : null,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('SAVE'),
          ),
        ],
      ),
      body: switch ((draft, _loadError)) {
        (_, final Object loadError) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Could not read from the radio: $loadError'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(onPressed: _reload, child: const Text('Retry')),
              ),
            ],
          ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        (final T draft, _) => AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...widget.fields(draft, () => setState(() {})),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ],
            ),
          ),
      },
    );
  }
}

String _label(ProtobufEnum value) => value.name
    .split('_')
    .map((word) => word.isEmpty ? word : word[0] + word.substring(1).toLowerCase())
    .join(' ');

Widget _enumField<E extends ProtobufEnum>({
  required String label,
  required E value,
  required List<E> values,
  required ValueChanged<E> onChanged,
}) =>
    DropdownButtonFormField<E>(
      initialValue: values.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label),
      items: [for (final v in values) DropdownMenuItem(value: v, child: Text(_label(v)))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );

/// Text field that edits a string inside a protobuf draft.
class _DraftTextField extends StatefulWidget {
  const _DraftTextField({
    required this.label,
    required this.initial,
    required this.onChanged,
    this.maxLength,
    this.keyboardType,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final int? maxLength;
  final TextInputType? keyboardType;

  @override
  State<_DraftTextField> createState() => _DraftTextFieldState();
}

class _DraftTextFieldState extends State<_DraftTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: widget.onChanged,
      );
}

class _OwnerEditor extends StatelessWidget {
  const _OwnerEditor({required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  Widget build(BuildContext context) => _AdminEditor<User>(
        title: 'Owner',
        load: radio.readOwner,
        save: radio.writeOwner,
        validate: (draft) =>
            BastionNodeIdentityValidation.longNameError(draft.longName) ??
            BastionNodeIdentityValidation.shortNameError(draft.shortName),
        fields: (draft, changed) => [
          _DraftTextField(
            label: 'Long name',
            initial: draft.longName,
            maxLength: 39,
            onChanged: (v) {
              draft.longName = v.trim();
              changed();
            },
          ),
          _DraftTextField(
            label: 'Short name',
            initial: draft.shortName,
            maxLength: 4,
            onChanged: (v) {
              draft.shortName = v.trim();
              changed();
            },
          ),
        ],
      );
}

class _LoraEditor extends StatelessWidget {
  const _LoraEditor({required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  Widget build(BuildContext context) => _AdminEditor<Config_LoRaConfig>(
        title: 'LoRa',
        load: () async => (await radio.readConfig(AdminMessage_ConfigType.LORA_CONFIG)).lora,
        save: (draft) => radio.writeConfig(Config(lora: draft)),
        validate: (draft) => draft.region == Config_LoRaConfig_RegionCode.UNSET
            ? 'Choose a region before saving; the radio will not transmit without one.'
            : null,
        warning: (original, draft) =>
            original.region != draft.region ||
                    original.modemPreset != draft.modemPreset ||
                    original.usePreset != draft.usePreset
                ? 'Changing region or modem preset disconnects this radio from '
                    'nodes that keep the old settings.'
                : null,
        fields: (draft, changed) => [
          _enumField(
            label: 'Region',
            value: draft.region,
            values: Config_LoRaConfig_RegionCode.values,
            onChanged: (v) {
              draft.region = v;
              changed();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use modem preset'),
            value: draft.usePreset,
            onChanged: (v) {
              draft.usePreset = v;
              changed();
            },
          ),
          if (draft.usePreset)
            _enumField(
              label: 'Modem preset',
              value: draft.modemPreset,
              values: Config_LoRaConfig_ModemPreset.values,
              onChanged: (v) {
                draft.modemPreset = v;
                changed();
              },
            ),
          const SizedBox(height: 16),
          Text('Hop limit: ${draft.hopLimit}'),
          Slider(
            value: draft.hopLimit.clamp(1, 7).toDouble(),
            min: 1,
            max: 7,
            divisions: 6,
            label: '${draft.hopLimit}',
            onChanged: (v) {
              draft.hopLimit = v.round();
              changed();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Transmit enabled'),
            subtitle: const Text('Off makes the radio receive-only'),
            value: draft.txEnabled,
            onChanged: (v) {
              draft.txEnabled = v;
              changed();
            },
          ),
        ],
      );
}

class _DeviceEditor extends StatelessWidget {
  const _DeviceEditor({required this.radio});

  final MeshtasticRadioCoordinator radio;

  static const _infrastructureRoles = {
    Config_DeviceConfig_Role.ROUTER,
    Config_DeviceConfig_Role.ROUTER_LATE,
    Config_DeviceConfig_Role.REPEATER,
  };

  @override
  Widget build(BuildContext context) => _AdminEditor<Config_DeviceConfig>(
        title: 'Device',
        load: () async => (await radio.readConfig(AdminMessage_ConfigType.DEVICE_CONFIG)).device,
        save: (draft) => radio.writeConfig(Config(device: draft)),
        warning: (original, draft) => original.role != draft.role &&
                _infrastructureRoles.contains(draft.role)
            ? '${_label(draft.role)} is for fixed infrastructure with good '
                'coverage. On a handheld it wastes airtime and battery.'
            : null,
        fields: (draft, changed) => [
          _enumField(
            label: 'Role',
            value: draft.role,
            // ROUTER_CLIENT is deprecated in firmware.
            values: Config_DeviceConfig_Role.values
                .where((r) => r != Config_DeviceConfig_Role.ROUTER_CLIENT)
                .toList(),
            onChanged: (v) {
              draft.role = v;
              changed();
            },
          ),
          _enumField(
            label: 'Rebroadcast mode',
            value: draft.rebroadcastMode,
            values: Config_DeviceConfig_RebroadcastMode.values,
            onChanged: (v) {
              draft.rebroadcastMode = v;
              changed();
            },
          ),
        ],
      );
}

class _PositionEditor extends StatelessWidget {
  const _PositionEditor({required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  Widget build(BuildContext context) => _AdminEditor<Config_PositionConfig>(
        title: 'Position',
        load: () async =>
            (await radio.readConfig(AdminMessage_ConfigType.POSITION_CONFIG)).position,
        save: (draft) => radio.writeConfig(Config(position: draft)),
        validate: (draft) => draft.positionBroadcastSecs != 0 && draft.positionBroadcastSecs < 30
            ? 'Broadcast interval must be 0 (firmware default) or at least 30 seconds.'
            : null,
        fields: (draft, changed) => [
          _enumField(
            label: 'GPS mode',
            value: draft.gpsMode,
            values: Config_PositionConfig_GpsMode.values,
            onChanged: (v) {
              draft.gpsMode = v;
              changed();
            },
          ),
          _DraftTextField(
            label: 'Broadcast interval (seconds, 0 = default)',
            initial: '${draft.positionBroadcastSecs}',
            keyboardType: TextInputType.number,
            onChanged: (v) {
              draft.positionBroadcastSecs = int.tryParse(v) ?? 0;
              changed();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Smart position broadcast'),
            subtitle: const Text('Send extra updates when the node moves'),
            value: draft.positionBroadcastSmartEnabled,
            onChanged: (v) {
              draft.positionBroadcastSmartEnabled = v;
              changed();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fixed position'),
            subtitle: const Text('Report the last known position instead of GPS'),
            value: draft.fixedPosition,
            onChanged: (v) {
              draft.fixedPosition = v;
              changed();
            },
          ),
        ],
      );
}

class _ChannelListPage extends StatefulWidget {
  const _ChannelListPage({required this.radio});

  final MeshtasticRadioCoordinator radio;

  @override
  State<_ChannelListPage> createState() => _ChannelListPageState();
}

class _ChannelListPageState extends State<_ChannelListPage> {
  final List<Channel> _channels = [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _channels.clear();
      _error = null;
      _loading = true;
    });
    try {
      for (var i = 0; i < 8; i++) {
        final channel = await widget.radio.readChannel(i);
        if (!mounted) return;
        setState(() => _channels.add(channel));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Channels'),
          actions: [
            IconButton(
              tooltip: 'Share as QR code',
              icon: const Icon(Icons.qr_code),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ChannelSharePage(radio: widget.radio),
              )),
            ),
            IconButton(
              tooltip: 'Import channel link',
              icon: const Icon(Icons.download),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChannelImportPage(radio: widget.radio),
                ));
                if (mounted) await _load();
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final channel in _channels)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${channel.index}')),
                  title: Text(channel.role == Channel_Role.DISABLED
                      ? 'Disabled'
                      : channel.settings.name.isEmpty
                          ? '(default name)'
                          : channel.settings.name),
                  subtitle: Text('${_label(channel.role)} • ${_describeKey(channel.settings.psk)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => _ChannelEditor(radio: widget.radio, index: channel.index),
                    ));
                    if (mounted) await _load();
                  },
                ),
              ),
            if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (_error != null) ...[
              Text('Could not read channels: $_error'),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(onPressed: _load, child: const Text('Retry')),
              ),
            ],
          ],
        ),
      );
}

String _describeKey(List<int> psk) => switch (psk.length) {
      0 => 'No encryption',
      1 when psk.first == 0 => 'No encryption',
      1 => 'Default key',
      16 => 'AES-128 key',
      32 => 'AES-256 key',
      _ => 'Unrecognized key',
    };

class _ChannelEditor extends StatelessWidget {
  const _ChannelEditor({required this.radio, required this.index});

  final MeshtasticRadioCoordinator radio;
  final int index;

  @override
  Widget build(BuildContext context) => _AdminEditor<Channel>(
        title: 'Channel $index',
        load: () => radio.readChannel(index),
        save: radio.writeChannel,
        validate: (draft) => BastionChannelValidation.validate(
          index: draft.index,
          role: draft.role.value,
          name: draft.settings.name,
          key: draft.settings.psk,
        ),
        warning: (original, draft) => BastionChannelValidation.requiresKeyChangeConfirmation(
          original.settings.psk,
          draft.settings.psk,
        )
            ? 'The encryption key changes. Nodes without the new key can no '
                'longer read this channel. Share it from the channel QR code.'
            : null,
        fields: (draft, changed) => [
          if (index != 0)
            _enumField(
              label: 'Role',
              value: draft.role,
              values: const [Channel_Role.SECONDARY, Channel_Role.DISABLED],
              onChanged: (v) {
                draft.role = v;
                changed();
              },
            ),
          _DraftTextField(
            label: 'Name (blank uses the preset name)',
            initial: draft.settings.name,
            maxLength: 11,
            onChanged: (v) {
              draft.ensureSettings().name = v;
              changed();
            },
          ),
          const SizedBox(height: 8),
          Text('Encryption: ${_describeKey(draft.settings.psk)}'),
          Wrap(spacing: 8, children: [
            OutlinedButton(
              onPressed: () {
                draft.ensureSettings().psk = const [1];
                changed();
              },
              child: const Text('Default key'),
            ),
            OutlinedButton(
              onPressed: () {
                final random = Random.secure();
                draft.ensureSettings().psk = List.generate(32, (_) => random.nextInt(256));
                changed();
              },
              child: const Text('New random AES-256'),
            ),
            OutlinedButton(
              onPressed: () {
                draft.ensureSettings().psk = const [0];
                changed();
              },
              child: const Text('No encryption'),
            ),
          ]),
        ],
      );
}
