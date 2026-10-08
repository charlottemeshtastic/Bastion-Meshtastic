export 'bastion_chat_message.dart';

import 'dart:async';
import 'dart:typed_data';

import 'bastion_chat_message.dart';
import 'bastion_message_archive.dart';
import 'meshtastic_connection_controller.dart';
import 'meshtastic_phoneapi_codec.dart';
import 'meshtastic_radio_session.dart';
import 'meshtastic_text_codec.dart';

/// One messaging pipeline for channels, DMs, durable offline queueing and Bot Mode.
class MeshtasticMessagingService {
  MeshtasticMessagingService({
    required this.session,
    required this.connection,
    this.archive,
    int Function()? packetIdFactory,
  }) : _packetIdFactory = packetIdFactory ?? _defaultPacketId;

  final MeshtasticRadioSession session;
  final MeshtasticConnectionController connection;
  final BastionMessageArchive? archive;
  final int Function() _packetIdFactory;

  final StreamController<MeshtasticTextMessage> _incoming =
      StreamController<MeshtasticTextMessage>.broadcast();
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<PendingTextMessage> _pending = [];
  final List<BastionChatMessage> _messages = [];
  final Set<String> _seen = {};
  final List<String> _seenOrder = [];
  final Map<int, DateTime> _lastBotReply = {};
  StreamSubscription? _subscription;
  bool _flushing = false;
  bool _started = false;
  bool _botEnabled = false;
  String _botReply =
      'Bastion is monitoring the mesh. I will reply when available.';
  int? localNodeNum;

  Stream<MeshtasticTextMessage> get incoming => _incoming.stream;
  Stream<void> get changes => _changes.stream;
  List<PendingTextMessage> get pending => List.unmodifiable(_pending);
  List<BastionChatMessage> get messages => List.unmodifiable(_messages);
  bool get botEnabled => _botEnabled;

  Future<void> start() async {
    if (!_started) {
      connection.addListener(_onConnectionChanged);
      _started = true;
    }
    if (archive != null && _messages.isEmpty && _pending.isEmpty) {
      final snapshot = await archive!.load();
      _messages.addAll(snapshot.messages);
      _pending.addAll(snapshot.pending);
      _trimHistory();
    }
    await _subscription?.cancel();
    _subscription = session.incomingEnvelopes.listen(_handleEnvelope);
    _notify();
  }

  void configureBot({
    required bool enabled,
    required String reply,
    int? nodeNum,
  }) {
    _botEnabled = enabled;
    _botReply = reply.trim().isEmpty
        ? 'Bastion is monitoring the mesh. I will reply when available.'
        : reply.trim();
    if (nodeNum != null) localNodeNum = nodeNum;
    _notify();
  }

  Future<int> sendText({
    required String text,
    int destination = MeshtasticTextCodec.broadcastNode,
    int channel = 0,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
    final id = _packetIdFactory() & 0xffffffff;
    final packetId = id == 0 ? 1 : id;
    final pending = PendingTextMessage(
      text: trimmed,
      destination: destination,
      channel: channel,
      packetId: packetId,
    );

    _messages.add(BastionChatMessage(
      packetId: packetId,
      from: localNodeNum ?? 0,
      to: destination,
      channel: channel,
      text: trimmed,
      timestamp: DateTime.now(),
      direction: BastionMessageDirection.outgoing,
      deliveryState: connection.isReady
          ? BastionDeliveryState.sent
          : BastionDeliveryState.queued,
    ));
    _trimHistory();

    if (!connection.isReady) {
      _pending.add(pending);
      _notify();
      return packetId;
    }

    try {
      await _send(pending);
      _notify();
    } catch (_) {
      _setDelivery(packetId, BastionDeliveryState.failed);
      rethrow;
    }
    return packetId;
  }

  Future<void> flush() async {
    if (_flushing || !connection.isReady) return;
    _flushing = true;
    try {
      while (_pending.isNotEmpty && connection.isReady) {
        final message = _pending.first;
        try {
          await _send(message);
          _pending.removeAt(0);
          _setDelivery(message.packetId, BastionDeliveryState.sent);
        } catch (_) {
          _setDelivery(message.packetId, BastionDeliveryState.failed);
          break;
        }
      }
    } finally {
      _flushing = false;
      _notify();
    }
  }

  Future<void> _send(PendingTextMessage message) {
    return session.send(MeshtasticTextCodec.toRadioText(
      text: message.text,
      destination: message.destination,
      channel: message.channel,
      packetId: message.packetId,
      wantAck: message.destination != MeshtasticTextCodec.broadcastNode,
    ));
  }

  void _handleEnvelope(Uint8List bytes) {
    try {
      final envelope = MeshtasticPhoneApiCodec.decodeFromRadio(bytes);
      if (envelope.kind != FromRadioPayloadKind.packet ||
          envelope.payload == null) {
        return;
      }
      final message = MeshtasticTextCodec.decodeMeshPacket(envelope.payload!);
      if (message == null) return;
      final key = '${message.from}:${message.packetId}';
      if (!_seen.add(key)) return;
      _seenOrder.add(key);
      if (_seenOrder.length > 2048) {
        _seen.remove(_seenOrder.removeAt(0));
      }

      if (localNodeNum != null && message.from == localNodeNum) return;

      _messages.add(BastionChatMessage(
        packetId: message.packetId,
        from: message.from,
        to: message.to,
        channel: message.channel,
        text: message.text,
        timestamp: message.rxTime == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(message.rxTime! * 1000),
        direction: BastionMessageDirection.incoming,
        deliveryState: BastionDeliveryState.received,
        rxSnr: message.rxSnr,
      ));
      _trimHistory();
      _incoming.add(message);
      _notify();
      unawaited(_maybeBotReply(message));
    } catch (error, stackTrace) {
      _incoming.addError(error, stackTrace);
    }
  }

  Future<void> _maybeBotReply(MeshtasticTextMessage message) async {
    final ownNode = localNodeNum;
    if (!_botEnabled || ownNode == null || !connection.isReady) return;
    if (message.from == ownNode) return;

    final text = message.text.trim();
    final lower = text.toLowerCase();
    if (lower.startsWith('bastion:')) return;

    final directToUs = message.to == ownNode;
    final isCommand = lower == '!help' || lower == '!status';
    if (!directToUs && !isCommand) return;

    final now = DateTime.now();
    final last = _lastBotReply[message.from];
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastBotReply[message.from] = now;

    final response = switch (lower) {
      '!help' => 'Bastion: commands !help !status',
      '!status' => 'Bastion: online • radio READY',
      _ => 'Bastion: $_botReply',
    };
    await sendText(
      text: response,
      destination: directToUs
          ? message.from
          : MeshtasticTextCodec.broadcastNode,
      channel: message.channel,
    );
  }

  void _onConnectionChanged() {
    if (connection.isReady) unawaited(flush());
  }

  void _setDelivery(int packetId, BastionDeliveryState state) {
    final index = _messages.lastIndexWhere((m) =>
        m.packetId == packetId &&
        m.direction == BastionMessageDirection.outgoing);
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(deliveryState: state);
    }
    _notify();
  }

  void _trimHistory() {
    if (_messages.length > 500) {
      _messages.removeRange(0, _messages.length - 500);
    }
  }

  void _notify() {
    if (archive != null) {
      unawaited(archive!.save(messages: _messages, pending: _pending));
    }
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async {
    if (_started) connection.removeListener(_onConnectionChanged);
    _started = false;
    await _subscription?.cancel();
    if (archive != null) {
      await archive!.save(messages: _messages, pending: _pending);
    }
    await _incoming.close();
    await _changes.close();
  }

  static int _defaultPacketId() =>
      DateTime.now().microsecondsSinceEpoch & 0xffffffff;
}
