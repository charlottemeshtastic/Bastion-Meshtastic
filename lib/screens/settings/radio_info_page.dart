import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/meshtastic/radio_session.dart';
import '../../services/diagnostics.dart';
import '../../services/connection/connection_manager.dart';

class RadioInfoPage extends StatelessWidget {
  const RadioInfoPage({super.key, required this.session, this.connection});
  final RadioSession session;
  final ConnectionManager? connection;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([session, if (connection != null) connection!]),
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'RADIO INFORMATION',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Configuration downloaded from your radio. Editing is not enabled yet.',
        ),
        ListTile(
          title: const Text('Connection'),
          subtitle: Text(session.status.name),
        ),
        const ListTile(
          title: Text('App version'),
          subtitle: Text('Bastion 0.5.0 · development build'),
        ),
        ListTile(
          title: const Text('Firmware'),
          subtitle: Text(session.firmware ?? 'Not downloaded'),
        ),
        ListTile(
          title: const Text('Local node'),
          subtitle: Text(
            session.localNode == null
                ? 'Unknown'
                : '!${session.localNode!.toRadixString(16).padLeft(8, '0')}',
          ),
        ),
        ListTile(
          title: const Text('Configuration sections'),
          subtitle: Text(
            session.configuration.keys.join(', ').isEmpty
                ? 'Not downloaded'
                : session.configuration.keys.join(', '),
          ),
        ),
        ListTile(
          title: const Text('Module sections'),
          subtitle: Text(
            session.modules.keys.join(', ').isEmpty
                ? 'Not downloaded'
                : session.modules.keys.join(', '),
          ),
        ),
        for (final channel in session.channels.values)
          ListTile(
            title: Text('Channel ${channel.index}'),
            subtitle: Text(
              channel.hasSettings() && channel.settings.name.isNotEmpty
                  ? channel.settings.name
                  : 'Unnamed channel',
            ),
            trailing: Text(channel.role.name),
          ),
        const SizedBox(height: 12),
        const Text(
          'CONNECTION DIAGNOSTICS',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ListTile(
          title: const Text('Malformed frames discarded'),
          subtitle: Text('${session.malformedFrames}'),
        ),
        ListTile(
          title: const Text('Monitoring'),
          subtitle: Text(
            session.readySince == null
                ? 'Paused'
                : 'Connected since ${session.readySince!.toLocal()} · ${connection?.screenOff == true ? 'screen-off service active' : 'foreground monitoring'}',
          ),
        ),
        const Text(
          'Copy a support summary without channel keys, messages, node coordinates or Bluetooth addresses.',
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('COPY DIAGNOSTICS'),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: radioDiagnostics(
                  session,
                  screenOff: connection?.screenOff ?? false,
                  autoReconnect: connection?.autoReconnect ?? false,
                ),
              ),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Diagnostics copied')),
              );
            }
          },
        ),
        OutlinedButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Bastion Meshtastic',
            applicationLegalese:
                'Independent Meshtastic companion. Protocol definitions: '
                'Meshtastic, GPL-3.0-only. See source repository NOTICE.md and protos/LICENSE.',
          ),
          child: const Text('OPEN SOURCE LICENSES'),
        ),
      ],
    ),
  );
}
