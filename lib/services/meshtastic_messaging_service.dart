export 'bastion_chat_message.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';

import '../generated/meshtastic/mesh.pb.dart' as pb;
import '../generated/meshtastic/portnums.pbenum.dart';
import '../generated/meshtastic/storeforward.pb.dart';
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

  /// A text message a store-and-forward router replays from its history.
  ///
  /// Replays arrive on STORE_FORWARD_APP, not TEXT_MESSAGE_APP. They carry
  /// the original packet id, so a message already received is de-duplicated.
  static MeshtasticTextMessage? storeForwardReplay(Uint8List meshPacket) {
    try {
      final packet = pb.MeshPacket.fromBuffer(meshPacket);
      if (!packet.hasDecoded() || packet.decoded.portnum != PortNum.STORE_FORWARD_APP) {
        return null;
      }
      final sf = StoreAndForward.fromBuffer(packet.decoded.payload);
      final broadcast = sf.rr == StoreAndForward_RequestResponse.ROUTER_TEXT_BROADCAST;
      if (!broadcast && sf.rr != StoreAndForward_RequestResponse.ROUTER_TEXT_DIRECT) {
        return null;
      }
      if (sf.text.isEmpty) return null;
      return MeshtasticTextMessage(
        packetId: sf.originalId != 0 ? sf.originalId : packet.id,
        from: packet.from,
        to: broadcast ? MeshtasticTextCodec.broadcastNode : packet.to,
        channel: packet.channel,
        text: utf8.decode(sf.text, allowMalformed: true),
        rxTime: packet.rxTime == 0 ? null : packet.rxTime,
        rxSnr: packet.rxSnr == 0 ? null : packet.rxSnr,
      );
    } on InvalidProtocolBufferException {
      return null;
    }
  }

  void _handleEnvelope(Uint8List bytes) {
    try {
      final envelope = MeshtasticPhoneApiCodec.decodeFromRadio(bytes);
      if (envelope.kind != FromRadioPayloadKind.packet ||
          envelope.payload == null) {
        return;
      }
      final ack = MeshtasticTextCodec.decodeRoutingAck(envelope.payload!);
      if (ack != null) {
        final matches = _messages.where((m) =>
            m.packetId == ack.requestId &&
            m.direction == BastionMessageDirection.outgoing &&
            m.to != MeshtasticTextCodec.broadcastNode &&
            m.to == ack.from &&
            m.deliveryState == BastionDeliveryState.sent);
        if (matches.isNotEmpty) {
          _setDelivery(ack.requestId, ack.errorReason == 0
              ? BastionDeliveryState.delivered
              : BastionDeliveryState.failed);
        }
        return;
      }
      final replay = storeForwardReplay(envelope.payload!);
      final message = replay ?? MeshtasticTextCodec.decodeMeshPacket(envelope.payload!);
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
      // Replayed history is old; auto-replying to it would spam the mesh.
      if (replay == null) unawaited(_maybeBotReply(message));
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
