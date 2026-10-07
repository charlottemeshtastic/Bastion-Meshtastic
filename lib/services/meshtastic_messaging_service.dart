import 'dart:async';
import 'dart:typed_data';

import 'meshtastic_connection_controller.dart';
import 'meshtastic_phoneapi_codec.dart';
import 'meshtastic_radio_session.dart';
import 'meshtastic_text_codec.dart';

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
  final List<PendingTextMessage> _pending = [];
  final Set<String> _seen = {};
  StreamSubscription? _subscription;

  Stream<MeshtasticTextMessage> get incoming => _incoming.stream;
  List<PendingTextMessage> get pending => List.unmodifiable(_pending);

  Future<void> start() async {
    await _subscription?.cancel();
    _subscription = session.incomingEnvelopes.listen(_handleEnvelope);
  }

  Future<int> sendText({
    required String text,
    int destination = MeshtasticTextCodec.broadcastNode,
    int channel = 0,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(text, 'text', 'must not be empty');
    final id = _packetIdFactory() & 0xffffffff;
    final packetId = id == 0 ? 1 : id;
    final message = PendingTextMessage(
      text: trimmed,
      destination: destination,
      channel: channel,
      packetId: packetId,
    );

    if (!connection.isReady) {
      _pending.add(message);
      return packetId;
    }
    await _send(message);
    return packetId;
  }

  Future<void> flush() async {
    if (!connection.isReady) return;
    while (_pending.isNotEmpty && connection.isReady) {
      final message = _pending.first;
      await _send(message);
      _pending.removeAt(0);
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
      if (_seen.length > 2048) _seen.clear();
      _incoming.add(message);
    } catch (error, stackTrace) {
      _incoming.addError(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _incoming.close();
  }

  static int _defaultPacketId() =>
      DateTime.now().microsecondsSinceEpoch & 0xffffffff;
}
