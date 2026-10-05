import 'meshtastic/radio_session.dart';

/// A bounded support summary. Never serializes configuration messages: those
/// can contain channel keys. No chat text, node positions or BLE addresses.
String radioDiagnostics(RadioSession session, {DateTime? now}) {
  final radio = session.localNode;
  final enabled = session.channels.values
      .where((c) => c.role.name != 'DISABLED')
      .length;
  return [
    'Bastion Meshtastic 0.4.0+4 · diagnostics',
    'Captured: ${(now ?? DateTime.now()).toUtc().toIso8601String()}',
    'Connection: ${session.status.name}',
    'Firmware: ${session.firmware ?? 'unknown'}',
    'Local node: ${radio == null ? 'unknown' : '!${radio.toRadixString(16).padLeft(8, '0')}'}',
    'Ready since: ${session.readySince?.toUtc().toIso8601String() ?? 'not monitoring'}',
    'Session nodes: ${session.nodes.length}',
    'Nodes with positions: ${session.nodes.where((n) => n.hasPosition).length}',
    'Enabled channels: $enabled',
    'Configuration sections: ${session.configuration.length}',
    'Module sections: ${session.modules.length}',
    'Malformed frames discarded: ${session.malformedFrames}',
    'Monitoring: foreground only; disconnects when app enters background',
    'Hardware interoperability validation: pending',
    'This summary excludes channel keys, chat text, node coordinates and BLE addresses.',
  ].join('\n');
}
