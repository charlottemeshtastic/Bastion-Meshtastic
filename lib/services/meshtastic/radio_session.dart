import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../generated/meshtastic/mesh.pb.dart' as pb;
import '../../generated/meshtastic/channel.pb.dart' as channel_pb;
import '../../generated/meshtastic/config.pb.dart' as config_pb;
import '../../generated/meshtastic/module_config.pb.dart' as module_pb;
import '../../generated/meshtastic/telemetry.pb.dart' as telemetry_pb;
import '../../generated/meshtastic/portnums.pbenum.dart';
import '../../models/mesh_node.dart';
import 'radio_transport.dart';

enum RadioStatus { disconnected, connecting, downloading, ready, error }

/// A verified protocol session. Readiness requires matching configuration nonce.
/// Radio configuration is read-only in this implementation.
class RadioSession extends ChangeNotifier {
  RadioSession({DateTime Function()? clock, int Function()? nonce,
    this.configTimeout = const Duration(seconds: 60)})
    : _clock = clock ?? DateTime.now,
      _nonce = nonce ?? (() => Random.secure().nextInt(0x7ffffffe) + 1);
  final DateTime Function() _clock;
  final int Function() _nonce;
  final Duration configTimeout;
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
  List<MeshNode> get nodes => List.unmodifiable(_nodes.values);
  RadioTransport? _transport;
  StreamSubscription<List<int>>? _frames;
  StreamSubscription<void>? _disconnects;
  Timer? _timeout;
  int _generation = 0;
  int _configId = 0;
  bool _disposed = false;
  final Set<String> _packets = {};
  int malformedFrames = 0;

  Future<void> connect(RadioTransport transport) async {
    await disconnect();
    if (_disposed) {
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
    _frames = transport.frames.listen((bytes) {
      if (generation == _generation && !_disposed) {
        _receive(bytes);
      }
    }, onError: (Object e) {
      if (generation == _generation) {
        _fail('Radio read failed: ${e.toString()}');
      }
    });
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
      _timeout = Timer(configTimeout, () =>
        _fail('Configuration timed out. Reconnect and check radio pairing.'));
      _notify();
      await transport.write(pb.ToRadio(wantConfigId: _configId).writeToBuffer());
    } catch (e) {
      if (generation == _generation && !_disposed) {
        _fail('Connection failed: ${e.toString()}');
      }
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
        modules[frame.moduleConfig.whichPayloadVariant().name] = frame.moduleConfig;
      }
      if (frame.hasChannel()) {
        channels[frame.channel.index] = frame.channel;
      }
      if (frame.hasNodeInfo()) {
        _nodeInfo(frame.nodeInfo);
      }
      if (frame.hasPacket()) {
        _packet(frame.packet);
      }
      if (frame.hasConfigCompleteId() && frame.configCompleteId == _configId &&
          status == RadioStatus.downloading) {
        if (localNode == null || localNode == 0 || localNode == 0xffffffff) {
          _fail('Radio did not provide a valid local node identity.');
          return;
        }
        _timeout?.cancel();
        readySince = _clock();
        status = RadioStatus.ready;
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
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    // A radio's invalid future clock must not suppress silence rules forever.
    return time.isAfter(_clock().add(const Duration(minutes: 5))) ? null : time;
  }

  void _nodeInfo(pb.NodeInfo info) {
    if (info.num == 0 || info.num == 0xffffffff) {
      return;
    }
    final old = _nodes[info.num];
    final heard = _timestamp(info.lastHeard);
    if (old?.lastHeard != null && heard != null && heard.isBefore(old!.lastHeard!)) {
      return;
    }
    final metrics = info.hasDeviceMetrics() ? info.deviceMetrics : null;
    final level = metrics != null && metrics.hasBatteryLevel() ? metrics.batteryLevel : null;
    final pos = info.hasPosition() ? info.position : null;
    final node = MeshNode(number: info.num,
      name: info.hasUser() ? info.user.longName : old?.name,
      lastHeard: heard ?? old?.lastHeard,
      battery: level == null ? old?.battery : (level <= 100 ? level : null),
      powered: level == null ? (old?.powered ?? false) : level > 100,
      snr: info.hasSnr() ? info.snr : old?.snr, rssi: old?.rssi,
      latitude: pos != null && pos.hasLatitudeI() ? pos.latitudeI * 1e-7 : old?.latitude,
      longitude: pos != null && pos.hasLongitudeI() ? pos.longitudeI * 1e-7 : old?.longitude,
      hops: info.hasHopsAway() ? info.hopsAway : old?.hops, viaMqtt: info.viaMqtt);
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
    if (packet.hasDecoded()) {
      final data = packet.decoded;
      if (data.portnum == PortNum.TELEMETRY_APP) {
        final telemetry = telemetry_pb.Telemetry.fromBuffer(data.payload);
        if (telemetry.hasDeviceMetrics() && telemetry.deviceMetrics.hasBatteryLevel()) {
          final level = telemetry.deviceMetrics.batteryLevel;
          battery = level <= 100 ? level : null;
          powered = level > 100;
        }
      } else if (data.portnum == PortNum.NODEINFO_APP) {
        final user = pb.User.fromBuffer(data.payload);
        name = user.longName;
      } else if (data.portnum == PortNum.POSITION_APP) {
        final position = pb.Position.fromBuffer(data.payload);
        latitude = position.hasLatitudeI() ? position.latitudeI * 1e-7 : latitude;
        longitude = position.hasLongitudeI() ? position.longitudeI * 1e-7 : longitude;
      }
    }
    final node = MeshNode(number: packet.from, name: name, lastHeard: heard,
      battery: battery, powered: powered, latitude: latitude, longitude: longitude,
      snr: packet.hasRxSnr() ? packet.rxSnr : old?.snr,
      rssi: packet.hasRxRssi() ? packet.rxRssi : old?.rssi,
      hops: old?.hops, viaMqtt: packet.viaMqtt);
    _nodes[node.number] = node;
    if (status == RadioStatus.ready) {
      _observations.add(node);
    }
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
    super.dispose();
  }
}
