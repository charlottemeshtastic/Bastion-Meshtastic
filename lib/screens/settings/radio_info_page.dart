import 'package:flutter/material.dart';
import '../../services/meshtastic/radio_session.dart';

class RadioInfoPage extends StatelessWidget {
  const RadioInfoPage({super.key, required this.session});
  final RadioSession session;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: session,
    builder: (context, _) => ListView(padding: const EdgeInsets.all(18), children: [
      const Text('RADIO INFORMATION', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const Text('Configuration downloaded from your radio. Editing is not enabled yet.'),
      ListTile(title: const Text('Connection'), subtitle: Text(session.status.name)),
      ListTile(title: const Text('Firmware'), subtitle: Text(session.firmware ?? 'Not downloaded')),
      ListTile(title: const Text('Local node'), subtitle: Text(session.localNode == null
        ? 'Unknown' : '!${session.localNode!.toRadixString(16).padLeft(8, '0')}')),
      ListTile(title: const Text('Configuration sections'),
        subtitle: Text(session.configuration.keys.join(', ').isEmpty
          ? 'Not downloaded' : session.configuration.keys.join(', '))),
      ListTile(title: const Text('Module sections'),
        subtitle: Text(session.modules.keys.join(', ').isEmpty
          ? 'Not downloaded' : session.modules.keys.join(', '))),
      for (final channel in session.channels.values)
        ListTile(title: Text('Channel ${channel.index}'),
          subtitle: Text(channel.hasSettings() && channel.settings.name.isNotEmpty
            ? channel.settings.name : 'Unnamed channel'),
          trailing: Text(channel.role.name)),
      OutlinedButton(onPressed: () => showLicensePage(context: context,
        applicationName: 'Bastion Meshtastic',
        applicationLegalese: 'Independent Meshtastic companion. Protocol definitions: '
          'Meshtastic, GPL-3.0-only. See source repository NOTICE.md and protos/LICENSE.'),
        child: const Text('OPEN SOURCE LICENSES')),
    ]));
}
