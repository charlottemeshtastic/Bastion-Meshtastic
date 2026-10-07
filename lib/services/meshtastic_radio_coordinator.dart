import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'bastion_chat_message.dart';
import 'bastion_message_archive.dart';
import 'meshtastic_ble_discovery.dart';
import 'meshtastic_connection_controller.dart';
import 'meshtastic_handshake.dart';
import 'meshtastic_messaging_service.dart';
import 'meshtastic_node_database.dart';
import 'meshtastic_phoneapi_codec.dart';
import 'meshtastic_radio_session.dart';
import 'meshtastic_radio_transport.dart';
import 'meshtastic_text_codec.dart';

/// Owns one verified Meshtastic radio session and exposes it to the UI.
class MeshtasticRadioCoordinator extends ChangeNotifier {
  MeshtasticRadioCoordinator() {
    connection.addListener(_relayConnectionChange);
    unawaited(_loadArchive());
  }

  final MeshtasticConnectionController connection =
      MeshtasticConnectionController();
  final BastionMessageArchive _archive = BastionMessageArchive();

  MeshtasticRadioSession? _session;
  MeshtasticHandshake? _handshake;
  MeshtasticNodeDatabase? _nodeDatabase;
  MeshtasticMessagingService? _messaging;
  StreamSubscription<List<MeshtasticNode>>? _nodeSubscription;
  StreamSubscription<void>? _messageSubscription;
  StreamSubscription<Uint8List>? _identitySubscription;
  List<MeshtasticNode> _nodes = const [];
  List<BastionChatMessage> _archivedMessages = const [];
  List<PendingTextMessage> _archivedPending = const [];
  bool _busy = false;
  bool _botEnabled = false;
  String _botReply =
      'Bastion is monitoring the mesh. I will reply when available.';
  int? _localNodeNum;

  List<MeshtasticNode> get nodes => _nodes;
  List<BastionChatMessage> get messages =>
      _messaging?.messages ?? _archivedMessages;
  int get pendingMessageCount =>
      _messaging?.pending.length ?? _archivedPending.length;
  bool get busy => _busy;
  bool get isReady => connection.isReady;
  int? get localNodeNum => _localNodeNum;

  Future<void> _loadArchive() async {
    final snapshot = await _archive.load();
    _archivedMessages = snapshot.messages;
    _archivedPending = snapshot.pending;
    notifyListeners();
  }

  void configureBot({required bool enabled, required String reply}) {
    _botEnabled = enabled;
    _botReply = reply;
    _messaging?.configureBot(
      enabled: enabled,
      reply: reply,
      nodeNum: _localNodeNum,
    );
    notifyListeners();
  }

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
        archive: _archive,
      );
      final handshake = MeshtasticHandshake(
        session: session,
        connection: connection,
      );

      _session = session;
      _nodeDatabase = nodeDatabase;
      _messaging = messaging;
      _handshake = handshake;

      _identitySubscription = session.incomingEnvelopes.listen((bytes) {
        final envelope = MeshtasticPhoneApiCodec.decodeFromRadio(bytes);
        if (envelope.kind == FromRadioPayloadKind.myInfo &&
            envelope.payload != null) {
          final nodeNum =
              MeshtasticPhoneApiCodec.decodeMyNodeNum(envelope.payload!);
          if (nodeNum != null) {
            _localNodeNum = nodeNum;
            messaging.configureBot(
              enabled: _botEnabled,
              reply: _botReply,
              nodeNum: nodeNum,
            );
            notifyListeners();
          }
        }
      });

      await nodeDatabase.start();
      await messaging.start();
      messaging.configureBot(
        enabled: _botEnabled,
        reply: _botReply,
        nodeNum: _localNodeNum,
      );
      _syncMessageSnapshot(messaging);
      _nodeSubscription = nodeDatabase.changes.listen((nodes) {
        _nodes = nodes;
        notifyListeners();
      });
      _messageSubscription = messaging.changes.listen((_) {
        _syncMessageSnapshot(messaging);
        notifyListeners();
      });

      await session.connect(deviceName: device.name);
      await handshake.synchronize();
      await messaging.flush();

      _nodes = nodeDatabase.nodes;
      _syncMessageSnapshot(messaging);
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
    int destination = MeshtasticTextCodec.broadcastNode,
    int channel = 0,
  }) async {
    final messaging = _messaging;
    if (messaging != null) {
      final id = await messaging.sendText(
        text: text,
        destination: destination,
        channel: channel,
      );
      _syncMessageSnapshot(messaging);
      notifyListeners();
      return id;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
    var packetId = DateTime.now().microsecondsSinceEpoch & 0xffffffff;
    if (packetId == 0) packetId = 1;
    final pending = PendingTextMessage(
      text: trimmed,
      destination: destination,
      channel: channel,
      packetId: packetId,
    );
    _archivedPending = [..._archivedPending, pending];
    _archivedMessages = [
      ..._archivedMessages,
      BastionChatMessage(
        packetId: packetId,
        from: _localNodeNum ?? 0,
        to: destination,
        channel: channel,
        text: trimmed,
        timestamp: DateTime.now(),
        direction: BastionMessageDirection.outgoing,
        deliveryState: BastionDeliveryState.queued,
      ),
    ];
    if (_archivedMessages.length > 500) {
      _archivedMessages =
          _archivedMessages.sublist(_archivedMessages.length - 500);
    }
    await _archive.save(
      messages: _archivedMessages,
      pending: _archivedPending,
    );
    notifyListeners();
    return packetId;
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

  void _syncMessageSnapshot(MeshtasticMessagingService messaging) {
    _archivedMessages = List.of(messaging.messages);
    _archivedPending = List.of(messaging.pending);
  }

  Future<void> _shutdownSession({required bool resetConnection}) async {
    final messaging = _messaging;
    if (messaging != null) _syncMessageSnapshot(messaging);
    await _nodeSubscription?.cancel();
    _nodeSubscription = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    await _handshake?.dispose();
    _handshake = null;
    await _messaging?.dispose();
    _messaging = null;
    await _nodeDatabase?.dispose();
    _nodeDatabase = null;
    await _session?.dispose();
    _session = null;
    _nodes = const [];
    _localNodeNum = null;
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
