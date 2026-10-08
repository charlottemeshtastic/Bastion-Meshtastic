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

  Map<String, Object?> toJson() => {
    'packetId': packetId,
    'from': from,
    'to': to,
    'channel': channel,
    'text': text,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'direction': direction.name,
    'deliveryState': deliveryState.name,
    if (rxSnr != null) 'rxSnr': rxSnr,
  };

  static BastionChatMessage fromJson(Map<String, Object?> json) {
    return BastionChatMessage(
      packetId: json['packetId']! as int,
      from: json['from']! as int,
      to: json['to']! as int,
      channel: json['channel']! as int,
      text: json['text']! as String,
      timestamp: DateTime.parse(json['timestamp']! as String).toLocal(),
      direction: BastionMessageDirection.values.byName(
        json['direction']! as String,
      ),
      deliveryState: BastionDeliveryState.values.byName(
        json['deliveryState']! as String,
      ),
      rxSnr: (json['rxSnr'] as num?)?.toDouble(),
    );
  }
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

  Map<String, Object?> toJson() => {
    'text': text,
    'destination': destination,
    'channel': channel,
    'packetId': packetId,
  };

  static PendingTextMessage fromJson(Map<String, Object?> json) =>
      PendingTextMessage(
        text: json['text']! as String,
        destination: json['destination']! as int,
        channel: json['channel']! as int,
        packetId: json['packetId']! as int,
      );
}
