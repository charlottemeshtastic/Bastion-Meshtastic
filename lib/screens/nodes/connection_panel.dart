import 'package:flutter/material.dart';
import '../../services/connection/connection_manager.dart';
import '../../services/meshtastic/radio_session.dart';

class ConnectionPanel extends StatelessWidget {
  const ConnectionPanel({super.key, required this.manager});
  final ConnectionManager manager;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: manager,
    builder: (context, _) => Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('screen-off-toggle'),
            title: const Text('Keep connection with screen off'),
            subtitle: const Text(
              'Android service with visible STOP control; up to 6 hours. Uses more battery.',
            ),
            value: manager.screenOff,
            onChanged:
                !manager.supported ||
                    manager.starting ||
                    (!manager.screenOff &&
                        manager.session.status != RadioStatus.ready)
                ? null
                : manager.setScreenOff,
          ),
          SwitchListTile(
            key: const Key('reconnect-toggle'),
            title: const Text('Recover dropped connections'),
            subtitle: Text(
              manager.retryPending
                  ? 'Retry ${manager.attempts + 1}/5 scheduled'
                  : 'Only the selected radio; 5 attempts with increasing delays. Never resends messages or re-enables Bot Mode.',
            ),
            value: manager.autoReconnect,
            onChanged: !manager.canRecover || manager.starting
                ? null
                : manager.setAutoReconnect,
          ),
          if (manager.starting) const LinearProgressIndicator(),
          if (manager.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                manager.error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Both options default off on launch. STOP disconnects and cancels recovery. '
              'Closing the app from Recents, force-stop or reboot ends the session. '
              'Phone battery restrictions may still interrupt it; device testing is required.',
            ),
          ),
        ],
      ),
    ),
  );
}
