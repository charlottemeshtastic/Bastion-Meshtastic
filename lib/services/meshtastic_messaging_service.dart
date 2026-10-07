import 'dart:async';
import 'dart:typed_data';

import 'meshtastic_connection_controller.dart';
import 'meshtastic_phoneapi_codec.dart';
import 'meshtastic_radio_session.dart';
import 'meshtastic_text_codec.dart';

enum BastionMessageDirection { incoming, outgoing }
enum BastionDeliveryState { received, queued, sent, failed }

class BastionChatMessage {
  const BastionChatMessage({
    required this.packetId,
    required this.from,
    required this.to,
    required this.channel,
    required this.text,
    required this.timestamp,
    required this.direction,
    required this.deliveryState,
    this.rxSnr,
  });

  final int packetId;
  final int from;
  final int to;
  final int channel;
  final String text;
  final DateTime timestamp;
  final BastionMessageDirection direction;
  final BastionDeliveryState deliveryState;
  final double? rxSnr;

  bool get isBroadcast => to == MeshtasticTextCodec.broadcastNode;

  BastionChatMessage copyWith({BastionDeliveryState? deliveryState}) =>
      BastionChatMessage(
        packetId: packetId,
        from: from,
        to: to,
        channel: channel,
        text: text,
        timestamp: timestamp,
        direction: direction,
        deliveryState: deliveryState ?? this.deliveryState,
        rxSnr: rxSnr,
      );
}

class PendingTextMessage {
  const PendingTextMessage({
    required this.text,
    required this.destination,
    required this.channel,
    required this.packetId,
  });
  final String text;
  final int destination;
  final int channel;
  final int packetId;
}

/// One messaging pipeline for channels, DMs, offline queueing and Bot Mode.
class MeshtasticMessagingService {
  MeshtasticMessagingService({
    required this.session,
    required this.connection,
    int Function()? packetIdFactory,
  }) : _packetIdFactory = packetIdFactory ?? _defaultPacketId;

  final MeshtasticRadioSession session;
  final MeshtasticConnectionController connection;
  final int Function() _packetIdFactory;

  final StreamController<MeshtasticTextMessage> _incoming =
      StreamController<MeshtasticTextMessage>.broadcast();
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<PendingTextMessage> _pending = [];
  final List<BastionChatMessage> _messages = [];
  final Set<String> _seen = {};
  final List<String> _seenOrder = [];
  StreamSubscription? _subscription;
  bool _flushing = false;
  bool _started = false;

  Stream<MeshtasticTextMessage> get incoming => _incoming.stream;
  Stream<void> get changes => _changes.stream;
  List<PendingTextMessage> get pending => List.unmodifiable(_pending);
  List<BastionChatMessage> get messages => List.unmodifiable(_messages);

  Future<void> start() async {
    if (!_started) {
      connection.addListener(_onConnectionChanged);
      _started = true;
    }
    await _subscription?.cancel();
    _subscription = session.incomingEnvelopes.listen(_handleEnvelope);
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
      from: 0,
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
      if (envelope.kind != FromRadioPayloadKind.packet || envelope.payload == null) {
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
    } catch (error, stackTrace) {
      _incoming.addError(error, stackTrace);
    }
  }

  void _onConnectionChanged() {
    if (connection.isReady) unawaited(flush());
  }

  void _setDelivery(int packetId, BastionDeliveryState state) {
    final index = _messages.lastIndexWhere((m) =>
        m.packetId == packetId &&
        m.direction == BastionMessageDirection.outgoing);
    if (index >= 0) _messages[index] = _messages[index].copyWith(deliveryState: state);
    _notify();
  }

  void _trimHistory() {
    if (_messages.length > 500) {
      _messages.removeRange(0, _messages.length - 500);
    }
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async {
    if (_started) connection.removeListener(_onConnectionChanged);
    _started = false;
    await _subscription?.cancel();
    await _incoming.close();
    await _changes.close();
  }

  static int _defaultPacketId() =>
      DateTime.now().microsecondsSinceEpoch & 0xffffffff;
}
