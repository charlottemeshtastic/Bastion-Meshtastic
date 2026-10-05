enum MessageState { received, writing, written, acknowledged, failed, unknown }

class ChatMessage {
  const ChatMessage({required this.key, required this.radio, required this.packetId,
    required this.from, required this.to, required this.channel, required this.text,
    required this.time, required this.outgoing, required this.state, this.detail});
  static const broadcast = 0xffffffff;
  final String key;
  final int radio;
  final int packetId;
  final int from;
  final int to;
  final int channel;
  final String text;
  final DateTime time;
  final bool outgoing;
  final MessageState state;
  final String? detail;
  bool get isDirect => to != broadcast;
  int get peer => outgoing ? to : from;
  ChatMessage withState(MessageState value, [String? reason]) => ChatMessage(
    key: key, radio: radio, packetId: packetId, from: from, to: to,
    channel: channel, text: text, time: time, outgoing: outgoing,
    state: value, detail: reason);
  String get statusLabel => switch (state) {
    MessageState.received => 'Received',
    MessageState.writing => 'Sending to radio…',
    MessageState.written => 'Written to radio · awaiting acknowledgement',
    MessageState.acknowledged => 'Mesh acknowledged · not a read receipt',
    MessageState.failed => 'Radio reported failure',
    MessageState.unknown => 'Delivery unconfirmed',
  };
  Map<String, Object?> toJson() => {'key': key, 'radio': radio, 'packetId': packetId,
    'from': from, 'to': to, 'channel': channel, 'text': text,
    'time': time.toIso8601String(), 'outgoing': outgoing, 'state': state.name, 'detail': detail};
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    key: json['key'] as String, radio: json['radio'] as int, packetId: json['packetId'] as int,
    from: json['from'] as int, to: json['to'] as int, channel: json['channel'] as int,
    text: json['text'] as String, time: DateTime.parse(json['time'] as String),
    outgoing: json['outgoing'] as bool, state: MessageState.values.byName(json['state'] as String),
    detail: json['detail'] as String?);
}
