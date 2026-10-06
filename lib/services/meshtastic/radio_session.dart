import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../generated/meshtastic/mesh.pb.dart' as pb;
import '../../generated/meshtastic/channel.pb.dart' as channel_pb;
import '../../generated/meshtastic/config.pb.dart' as config_pb;
import '../../generated/meshtastic/module_config.pb.dart' as module_pb;
import '../../generated/meshtastic/telemetry.pb.dart' as telemetry_pb;
import '../../generated/meshtastic/portnums.pbenum.dart';
import '../../models/mesh_node.dart';
import '../../models/chat_message.dart';
import '../../models/telemetry_sample.dart';
import 'radio_transport.dart';

enum RadioStatus { disconnected, connecting, downloading, ready, error }

/// A verified protocol session. Readiness requires matching configuration nonce.
/// Radio configuration is read-only in this implementation.
class RadioSession extends ChangeNotifier {
  RadioSession({
    DateTime Function()? clock,
    int Function()? nonce,
    int Function()? packetId,
    this.ackTimeout = const Duration(seconds: 90),
    this.configTimeout = const Duration(seconds: 60),
  }) : _clock = clock ?? DateTime.now,
       _packetId = packetId ?? (() => Random.secure().nextInt(0x7ffffffe) + 1),
       _nonce = nonce ?? (() => Random.secure().nextInt(0x7ffffffe) + 1);
  final DateTime Function() _clock;
  final int Function() _nonce;
  final Duration configTimeout;
  final Duration ackTimeout;
  final int Function() _packetId;
  final _messages = StreamController<ChatMessage>.broadcast(sync: true);
  Stream<ChatMessage> get messages => _messages.stream;
  final Map<int, ChatMessage> _outgoing = {};
  final Map<int, Timer> _ackTimers = {};
  final Set<int> _sentIds = {};
  final List<pb.MeshPacket> _earlyMessages = [];
  int _receiveSequence = 0;
  RadioStatus status = RadioStatus.disconnected;
  String? error;
  int? localNode;
  String? firmware;
  DateTime? readySince;
  final Map<int, MeshNode> _nodes = {};
  final Map<int, channel_pb.Channel> channels = {};
  final Map<String, config_pb.Config> configuration = {};
  final Map<String, module_pb.ModuleConfig> modules = {};
  final _observations = StreamController<MeshNode>.broadcast(sync: true);
  Stream<MeshNode> get observations => _observations.stream;
  final _telemetry = StreamController<TelemetrySample>.broadcast(sync: true);
  Stream<TelemetrySample> get telemetry => _telemetry.stream;
  List<MeshNode> get nodes => List.unmodifiable(_nodes.values);
  RadioTransport? _transport;
  StreamSubscription<List<int>>? _frames;
  StreamSubscription<void>? _disconnects;
  Timer? _timeout;
  int _generation = 0;
  int _configId = 0;
  bool _disposed = false;
  bool _opening = false;
  final Set<String> _packets = {};
  int malformedFrames = 0;

  Future<void> connect(RadioTransport transport) async {
    if (_opening || _disposed) {
      return;
    }
    _opening = true;
    await disconnect();
    if (_disposed) {
      _opening = false;
      return;
    }
    final generation = ++_generation;
    _transport = transport;
    _nodes.clear();
    channels.clear();
    configuration.clear();
    modules.clear();
    _packets.clear();
    localNode = null;
    firmware = null;
    readySince = null;
    error = null;
    status = RadioStatus.connecting;
    _notify();
    _frames = transport.frames.listen(
      (bytes) {
        if (generation == _generation && !_disposed) {
          _receive(bytes);
        }
      },
      onError: (Object e) {
        if (generation == _generation) {
          _fail('Radio read failed: ${e.toString()}');
        }
      },
    );
    _disconnects = transport.disconnections.listen((_) {
      if (generation == _generation) {
        unawaited(disconnect());
      }
    });
    try {
      await transport.open();
      if (generation != _generation || _disposed) {
        await transport.close();
        return;
      }
      status = RadioStatus.downloading;
      _configId = _nonce();
      _timeout = Timer(
        configTimeout,
        () => _fail(
          'Configuration timed out. Reconnect and check radio pairing.',
        ),
      );
      _notify();
      await transport.write(
        pb.ToRadio(wantConfigId: _configId).writeToBuffer(),
      );
    } catch (e) {
      if (generation == _generation && !_disposed) {
        _fail('Connection failed: ${e.toString()}');
      }
    } finally {
      _opening = false;
    }
  }

  void _receive(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    try {
      final frame = pb.FromRadio.fromBuffer(bytes);
      if (frame.hasRebooted() && frame.rebooted) {
        _fail('Radio rebooted. Reconnect to download configuration again.');
        return;
      }
      if (frame.hasMyInfo()) {
        localNode = frame.myInfo.myNodeNum;
      }
      if (frame.hasMetadata()) {
        firmware = frame.metadata.firmwareVersion;
      }
      if (frame.hasConfig()) {
        configuration[frame.config.whichPayloadVariant().name] = frame.config;
      }
      if (frame.hasModuleConfig()) {
        modules[frame.moduleConfig.whichPayloadVariant().name] =
            frame.moduleConfig;
      }
      if (frame.hasChannel()) {
        channels[frame.channel.index] = frame.channel;
      }
      if (frame.hasNodeInfo()) {
        _nodeInfo(frame.nodeInfo);
      }
      if (frame.hasQueueStatus()) {
        final queue = frame.queueStatus;
        if (queue.res != 0) {
          _updateMessage(
            queue.meshPacketId,
            MessageState.failed,
            'Radio queue rejected the packet (code ${queue.res}).',
          );
        }
      }
      if (frame.hasPacket()) {
        _packet(frame.packet);
      }
      if (frame.hasConfigCompleteId() &&
          frame.configCompleteId == _configId &&
          status == RadioStatus.downloading) {
        if (localNode == null || localNode == 0 || localNode == 0xffffffff) {
          _fail('Radio did not provide a valid local node identity.');
          return;
        }
        _timeout?.cancel();
        readySince = _clock();
        status = RadioStatus.ready;
        for (final packet in _earlyMessages) {
          _messagePacket(packet);
        }
        _earlyMessages.clear();
      }
      _notify();
    } catch (_) {
      malformedFrames++;
      // Bad protobuf frames are discarded without destroying a working session.
      _notify();
    }
  }

  DateTime? _timestamp(int seconds) {
    if (seconds <= 0) {
      return null;
    }
    final time = DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    );
    // A radio's invalid future clock must not suppress silence rules forever.
    return time.isAfter(_clock().add(const Duration(minutes: 5))) ? null : time;
  }

  void _nodeInfo(pb.NodeInfo info) {
    if (info.num == 0 || info.num == 0xffffffff) {
      return;
    }
    final old = _nodes[info.num];
    final heard = _timestamp(info.lastHeard);
    if (old?.lastHeard != null &&
        heard != null &&
        heard.isBefore(old!.lastHeard!)) {
      return;
    }
    final metrics = info.hasDeviceMetrics() ? info.deviceMetrics : null;
    final level = metrics != null && metrics.hasBatteryLevel()
        ? metrics.batteryLevel
        : null;
    final pos = info.hasPosition() ? info.position : null;
    final validPos =
        pos != null &&
        pos.hasLatitudeI() &&
        pos.hasLongitudeI() &&
        MeshNode.validPosition(pos.latitudeI * 1e-7, pos.longitudeI * 1e-7);
    final node = MeshNode(
      number: info.num,
      name: info.hasUser() ? info.user.longName : old?.name,
      lastHeard: heard ?? old?.lastHeard,
      battery: level == null ? old?.battery : (level <= 100 ? level : null),
      powered: level == null ? (old?.powered ?? false) : level > 100,
      snr: info.hasSnr() ? info.snr : old?.snr,
      rssi: old?.rssi,
      latitude: validPos ? pos.latitudeI * 1e-7 : old?.latitude,
      longitude: validPos ? pos.longitudeI * 1e-7 : old?.longitude,
      positionTime: validPos
          ? (_timestamp(pos.time) ?? heard)
          : old?.positionTime,
      hops: info.hasHopsAway() ? info.hopsAway : old?.hops,
      viaMqtt: info.viaMqtt,
    );
    _nodes[node.number] = node;
    if (status == RadioStatus.ready) {
      _observations.add(node);
    }
  }

  void _packet(pb.MeshPacket packet) {
    if (packet.from == 0 || packet.from == 0xffffffff) {
      return;
    }
    if (packet.id != 0) {
      final key = '${packet.from}:${packet.id}';
      if (!_packets.add(key)) {
        return;
      }
      if (_packets.length > 2048) {
        _packets.remove(_packets.first);
      }
    }
    if (packet.hasDecoded() &&
        (packet.decoded.portnum == PortNum.TEXT_MESSAGE_APP ||
            packet.decoded.portnum == PortNum.ROUTING_APP)) {
      if (status == RadioStatus.ready) {
        _messagePacket(packet);
      } else if (_earlyMessages.length < 100) {
        _earlyMessages.add(packet);
      }
    }
    final old = _nodes[packet.from];
    final heard = _timestamp(packet.rxTime) ?? _clock();
    if (old?.lastHeard != null && heard.isBefore(old!.lastHeard!)) {
      return;
    }
    var name = old?.name;
    var battery = old?.battery;
    var powered = old?.powered ?? false;
    var latitude = old?.latitude;
    var longitude = old?.longitude;
    var positionTime = old?.positionTime;
    telemetry_pb.DeviceMetrics? metrics;
    if (packet.hasDecoded()) {
      final data = packet.decoded;
      if (data.portnum == PortNum.TELEMETRY_APP) {
        final telemetry = telemetry_pb.Telemetry.fromBuffer(data.payload);
        metrics = telemetry.hasDeviceMetrics() ? telemetry.deviceMetrics : null;
        if (telemetry.hasDeviceMetrics() &&
            telemetry.deviceMetrics.hasBatteryLevel()) {
          final level = telemetry.deviceMetrics.batteryLevel;
          battery = level <= 100 ? level : null;
          powered = level > 100;
        }
      } else if (data.portnum == PortNum.NODEINFO_APP) {
        final user = pb.User.fromBuffer(data.payload);
        name = user.longName;
      } else if (data.portnum == PortNum.POSITION_APP) {
        final position = pb.Position.fromBuffer(data.payload);
        if (position.hasLatitudeI() &&
            position.hasLongitudeI() &&
            MeshNode.validPosition(
              position.latitudeI * 1e-7,
              position.longitudeI * 1e-7,
            )) {
          latitude = position.latitudeI * 1e-7;
          longitude = position.longitudeI * 1e-7;
          positionTime = _timestamp(position.time) ?? heard;
        }
      }
    }
    final node = MeshNode(
      number: packet.from,
      name: name,
      lastHeard: heard,
      battery: battery,
      powered: powered,
      latitude: latitude,
      longitude: longitude,
      positionTime: positionTime,
      snr: packet.hasRxSnr() ? packet.rxSnr : old?.snr,
      rssi: packet.hasRxRssi() ? packet.rxRssi : old?.rssi,
      hops: old?.hops,
      viaMqtt: packet.viaMqtt,
    );
    _nodes[node.number] = node;
    if (status == RadioStatus.ready) {
      _observations.add(node);
      final level = metrics != null && metrics.hasBatteryLevel()
          ? metrics.batteryLevel
          : null;
      final sample = TelemetrySample(
        radio: localNode!,
        viaMqtt: packet.viaMqtt,
        node: packet.from,
        time: heard,
        battery: level != null && level <= 100 ? level : null,
        powered: level == null ? null : level > 100,
        voltage: metrics != null && metrics.hasVoltage()
            ? metrics.voltage
            : null,
        channelUtilization: metrics != null && metrics.hasChannelUtilization()
            ? metrics.channelUtilization
            : null,
        airUtilization: metrics != null && metrics.hasAirUtilTx()
            ? metrics.airUtilTx
            : null,
        snr: packet.hasRxSnr() ? packet.rxSnr : null,
        rssi: packet.hasRxRssi() ? packet.rxRssi : null,
      );
      if (sample.hasValues) {
        _telemetry.add(sample);
      }
    }
  }

  Future<void> sendText(
    String text, {
    required int channel,
    int destination = ChatMessage.broadcast,
  }) async {
    final transport = _transport;
    final radio = localNode;
    if (status != RadioStatus.ready || transport == null || radio == null) {
      throw StateError(
        'Connect and finish radio configuration before sending.',
      );
    }
    final payload = utf8.encode(text.trim());
    if (payload.isEmpty ||
        payload.length > pb.Constants.DATA_PAYLOAD_LEN.value) {
      throw ArgumentError('Messages must contain 1–233 UTF-8 bytes.');
    }
    final selected = channels[channel];
    if (selected == null || selected.role == channel_pb.Channel_Role.DISABLED) {
      throw StateError('Choose an enabled channel downloaded from your radio.');
    }
    if (destination <= 0 ||
        destination > ChatMessage.broadcast ||
        destination == radio) {
      throw ArgumentError('Choose a valid remote destination.');
    }
    var id = _packetId();
    for (var i = 0; _sentIds.contains(id) && i < 10; i++) {
      id = _packetId();
    }
    if (id <= 0 || id > 0xffffffff || !_sentIds.add(id)) {
      throw StateError('Could not allocate a unique packet ID.');
    }
    final message = ChatMessage(
      key: '$radio:$radio:$id',
      radio: radio,
      packetId: id,
      from: radio,
      to: destination,
      channel: channel,
      text: text.trim(),
      time: _clock(),
      outgoing: true,
      state: MessageState.writing,
    );
    _outgoing[id] = message;
    _messages.add(message);
    final generation = _generation;
    var hopLimit = 3;
    final lora = configuration['lora'];
    if (lora != null && lora.hasLora()) {
      hopLimit = lora.lora.hopLimit;
    }
    final packet = pb.MeshPacket(
      from: radio,
      to: destination,
      channel: channel,
      id: id,
      wantAck: true,
      hopLimit: hopLimit,
      decoded: pb.Data(portnum: PortNum.TEXT_MESSAGE_APP, payload: payload),
    );
    _ackTimers[id] = Timer(
      ackTimeout,
      () => _updateMessage(
        id,
        MessageState.unknown,
        'No mesh acknowledgement arrived before the timeout.',
      ),
    );
    try {
      await transport.write(pb.ToRadio(packet: packet).writeToBuffer());
      // A synchronous ACK or disconnect must not be downgraded after the write.
      if (generation == _generation &&
          _outgoing[id]?.state == MessageState.writing) {
        _updateMessage(id, MessageState.written);
      }
    } catch (_) {
      if (_outgoing[id]?.state == MessageState.writing) {
        _updateMessage(
          id,
          MessageState.unknown,
          'Bluetooth write failed; delivery could not be confirmed.',
        );
      }
      rethrow;
    }
  }

  void _updateMessage(int id, MessageState state, [String? reason]) {
    final message = _outgoing[id];
    if (message == null ||
        _disposed ||
        message.state == MessageState.acknowledged ||
        message.state == MessageState.failed) {
      return;
    }
    if (state != MessageState.written) {
      _ackTimers.remove(id)?.cancel();
    }
    final updated = message.withState(state, reason);
    _outgoing[id] = updated;
    _messages.add(updated);
  }

  void _messagePacket(pb.MeshPacket packet) {
    final radio = localNode;
    if (radio == null || !packet.hasDecoded()) {
      return;
    }
    final data = packet.decoded;
    if (data.portnum == PortNum.ROUTING_APP && data.requestId != 0) {
      final outgoing = _outgoing[data.requestId];
      if (outgoing == null ||
          packet.to != radio ||
          (outgoing.isDirect &&
              packet.from != outgoing.to &&
              packet.from != radio)) {
        return;
      }
      final routing = pb.Routing.fromBuffer(data.payload);
      if (!routing.hasErrorReason()) {
        return;
      }
      _updateMessage(
        data.requestId,
        routing.errorReason == pb.Routing_Error.NONE
            ? MessageState.acknowledged
            : MessageState.failed,
        routing.errorReason == pb.Routing_Error.NONE
            ? null
            : routing.errorReason.name,
      );
    } else if (data.portnum == PortNum.TEXT_MESSAGE_APP &&
        (packet.to == radio || packet.to == ChatMessage.broadcast) &&
        packet.from != radio) {
      final text = utf8.decode(data.payload, allowMalformed: true);
      if (text.isEmpty) {
        return;
      }
      final suffix = packet.id == 0
          ? 'zero:${_clock().microsecondsSinceEpoch}:${_receiveSequence++}'
          : packet.id.toString();
      _messages.add(
        ChatMessage(
          key: '$radio:${packet.from}:$suffix',
          radio: radio,
          packetId: packet.id,
          from: packet.from,
          to: packet.to,
          channel: packet.channel,
          text: text,
          time: _timestamp(packet.rxTime) ?? _clock(),
          outgoing: false,
          state: MessageState.received,
        ),
      );
    }
  }

  void _interruptMessages() {
    for (final id in _outgoing.keys.toList()) {
      final state = _outgoing[id]!.state;
      if (state == MessageState.writing || state == MessageState.written) {
        _updateMessage(
          id,
          MessageState.unknown,
          'Radio disconnected before confirmation.',
        );
      }
    }
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    _ackTimers.clear();
    _outgoing.clear();
    _earlyMessages.clear();
  }

  void _fail(String message) {
    error = message;
    status = RadioStatus.error;
    readySince = null;
    _timeout?.cancel();
    _notify();
    unawaited(_closeTransport());
  }

  Future<void> _closeTransport() async {
    ++_generation;
    _interruptMessages();
    final transport = _transport;
    _transport = null;
    final frames = _frames;
    final disconnects = _disconnects;
    _frames = null;
    _disconnects = null;
    await frames?.cancel();
    await disconnects?.cancel();
    try {
      await transport?.close();
    } catch (_) {
      // UI reports original failure; teardown errors must not escape.
    }
  }

  Future<void> disconnect() async {
    _timeout?.cancel();
    readySince = null;
    status = RadioStatus.disconnected;
    _notify();
    await _closeTransport();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    unawaited(_closeTransport());
    unawaited(_observations.close());
    unawaited(_messages.close());
    unawaited(_telemetry.close());
    super.dispose();
  }
}
