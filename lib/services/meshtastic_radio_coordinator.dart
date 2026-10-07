import 'dart:async';

import 'package:flutter/foundation.dart';

import 'meshtastic_ble_discovery.dart';
import 'meshtastic_connection_controller.dart';
import 'meshtastic_handshake.dart';
import 'meshtastic_messaging_service.dart';
import 'meshtastic_node_database.dart';
import 'meshtastic_radio_session.dart';
import 'meshtastic_radio_transport.dart';

/// Owns one verified Meshtastic radio session and exposes it to the UI.
///
/// The coordinator is the bridge between BLE discovery and Bastion's protocol
/// services: transport -> session -> handshake -> NodeDB + COMMS.
class MeshtasticRadioCoordinator extends ChangeNotifier {
  MeshtasticRadioCoordinator() {
    connection.addListener(_relayConnectionChange);
  }

  final MeshtasticConnectionController connection =
      MeshtasticConnectionController();

  MeshtasticRadioSession? _session;
  MeshtasticHandshake? _handshake;
  MeshtasticNodeDatabase? _nodeDatabase;
  MeshtasticMessagingService? _messaging;
  StreamSubscription<List<MeshtasticNode>>? _nodeSubscription;
  StreamSubscription<void>? _messageSubscription;
  List<MeshtasticNode> _nodes = const [];
  bool _busy = false;

  List<MeshtasticNode> get nodes => _nodes;
  List<BastionChatMessage> get messages => _messaging?.messages ?? const [];
  int get pendingMessageCount => _messaging?.pending.length ?? 0;
  bool get busy => _busy;
  bool get isReady => connection.isReady;

  Future<void> connect(MeshtasticBleDevice device) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();

    try {
      await _shutdownSession(resetConnection: false);

      final transport = MeshtasticUniversalBleTransport(deviceId: device.id);
      final session = MeshtasticRadioSession(
        transport: transport,
        connection: connection,
      );
      final nodeDatabase = MeshtasticNodeDatabase(session);
      final messaging = MeshtasticMessagingService(
        session: session,
        connection: connection,
      );
      final handshake = MeshtasticHandshake(
        session: session,
        connection: connection,
      );

      _session = session;
      _nodeDatabase = nodeDatabase;
      _messaging = messaging;
      _handshake = handshake;

      await nodeDatabase.start();
      await messaging.start();
      _nodeSubscription = nodeDatabase.changes.listen((nodes) {
        _nodes = nodes;
        notifyListeners();
      });
      _messageSubscription = messaging.changes.listen((_) => notifyListeners());

      await session.connect(deviceName: device.name);
      await handshake.synchronize();
      await messaging.flush();

      _nodes = nodeDatabase.nodes;
      notifyListeners();
    } catch (_) {
      await _shutdownSession(resetConnection: false);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<int> sendText({
    required String text,
    int destination = 0xffffffff,
    int channel = 0,
  }) async {
    final messaging = _messaging;
    if (messaging == null) {
      throw StateError('Connect a Meshtastic radio before opening COMMS.');
    }
    final id = await messaging.sendText(
      text: text,
      destination: destination,
      channel: channel,
    );
    notifyListeners();
    return id;
  }

  Future<void> disconnect() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _shutdownSession(resetConnection: true);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _shutdownSession({required bool resetConnection}) async {
    await _nodeSubscription?.cancel();
    _nodeSubscription = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _handshake?.dispose();
    _handshake = null;
    await _messaging?.dispose();
    _messaging = null;
    await _nodeDatabase?.dispose();
    _nodeDatabase = null;
    await _session?.dispose();
    _session = null;
    _nodes = const [];
    if (resetConnection) connection.disconnect();
  }

  void _relayConnectionChange() => notifyListeners();

  @override
  void dispose() {
    connection.removeListener(_relayConnectionChange);
    unawaited(_shutdownSession(resetConnection: true));
    super.dispose();
  }
}
