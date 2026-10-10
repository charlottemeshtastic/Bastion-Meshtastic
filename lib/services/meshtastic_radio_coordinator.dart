import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../generated/meshtastic/admin.pb.dart';
import '../generated/meshtastic/apponly.pb.dart';
import '../generated/meshtastic/channel.pb.dart';
import '../generated/meshtastic/config.pb.dart';
import '../generated/meshtastic/mesh.pb.dart' as pb show Data, FromRadio, MeshPacket, Position, ToRadio;
import '../generated/meshtastic/mesh.pb.dart' show User;
import '../generated/meshtastic/module_config.pb.dart';
import '../generated/meshtastic/portnums.pbenum.dart';
import '../generated/meshtastic/telemetry.pb.dart';
import 'bastion_admin_packet_codec.dart';
import 'bastion_background_service.dart';
import 'bastion_bluetooth_state.dart';
import 'bastion_message_alerts.dart';
import 'bastion_phone_position.dart';
import 'bastion_waypoints.dart';
import 'bastion_owner_codec.dart';
import 'bastion_owner_readback.dart';
import 'bastion_message_archive.dart';
import 'bastion_radio_config_codec.dart';
import 'bastion_reconnect_policy.dart';
import 'bastion_reconnect_supervisor.dart';
import 'bastion_telemetry_codec.dart';
import 'bastion_nodedex.dart';
import 'meshtastic_ble_discovery.dart';
import 'meshtastic_connection_controller.dart';
import 'meshtastic_admin_session.dart';
import 'meshtastic_handshake.dart';
import 'meshtastic_messaging_service.dart';
import 'meshtastic_node_database.dart';
import 'meshtastic_phoneapi_codec.dart';
import 'meshtastic_radio_session.dart';
import 'meshtastic_radio_transport.dart';
import 'meshtastic_text_codec.dart';
import 'meshtastic_traceroute.dart';

/// Owns one verified Meshtastic radio session and exposes it to the UI.
class MeshtasticRadioCoordinator extends ChangeNotifier {
  MeshtasticRadioCoordinator({
    BastionBackgroundKeeper? background,
    BastionMessageAlerts? alerts,
    PhoneLocationSource? location,
    BluetoothAvailability? bluetooth,
  })  : _background = background ?? BastionForegroundService(),
        _bluetooth = bluetooth ?? UniversalBleAvailability(),
        _alerts = alerts ?? BastionLocalMessageAlerts(),
        _location = location ?? GeolocatorLocationSource() {
    unawaited(_loadSharePreference());
    _bluetoothSubscription = _bluetooth.changes.listen(_handleBluetoothChange);
    unawaited(_waypoints.load().then((_) => notifyListeners()));
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _inForeground = state == AppLifecycleState.resumed,
    );
    connection.addListener(_relayConnectionChange);
    unawaited(_loadArchive());
    unawaited(_loadNodeDex());
  }

  final MeshtasticConnectionController connection =
      MeshtasticConnectionController();
  final BastionMessageArchive _archive = BastionMessageArchive();
  final BastionNodeDex _nodeDex = BastionNodeDex();
  final BastionBackgroundKeeper _background;
  final BastionMessageAlerts _alerts;
  final PhoneLocationSource _location;
  final BluetoothAvailability _bluetooth;
  late final StreamSubscription<bool> _bluetoothSubscription;
  bool _bluetoothOn = true;

  /// A link was lost while Bluetooth was off; reconnect when it returns.
  bool _waitingForBluetooth = false;
  final BastionWaypointStore _waypoints = BastionWaypointStore();
  StreamSubscription<Uint8List>? _waypointSubscription;
  static const _sharePreferenceKey = 'bastion.share_phone_location';
  bool _sharePhoneLocation = false;
  BastionPhonePositionSharer? _sharer;
  String? _locationShareProblem;
  late final AppLifecycleListener _lifecycle;
  bool _inForeground = true;
  late final BastionReconnectSupervisor _reconnect =
      BastionReconnectSupervisor(
    reconnect: _reconnectLastDevice,
    mayReconnect: () =>
        _lastDevice != null &&
        BastionReconnectPolicy.shouldReconnect(
          userDisconnected: _userDisconnected,
          bluetoothEnabled: _bluetoothOn,
        ),
  );

  MeshtasticRadioSession? _session;
  MeshtasticHandshake? _handshake;
  MeshtasticNodeDatabase? _nodeDatabase;
  MeshtasticMessagingService? _messaging;
  MeshtasticAdminSession? _admin;
  MeshtasticTraceroute? _traceroute;
  StreamSubscription<List<MeshtasticNode>>? _nodeSubscription;
  StreamSubscription<MeshtasticNode>? _nodeDexSubscription;
  StreamSubscription<void>? _messageSubscription;
  StreamSubscription<Uint8List>? _identitySubscription;
  StreamSubscription<void>? _linkLossSubscription;
  StreamSubscription<MeshtasticTextMessage>? _incomingSubscription;
  MeshtasticBleDevice? _lastDevice;
  bool _userDisconnected = false;
  List<MeshtasticNode> _nodes = const [];
  List<BastionChatMessage> _archivedMessages = const [];
  List<PendingTextMessage> _archivedPending = const [];
  bool _busy = false;
  bool _botEnabled = false;
  String _botReply =
      'Bastion is monitoring the mesh. I will reply when available.';
  int? _localNodeNum;
  final List<double> _snrHistory = [];
  int _receivedTextPackets = 0;
  final Map<int, BastionDeviceTelemetry> _deviceTelemetry = {};
  final List<Uint8List> _radioConfigSnapshots = [];
  final List<Uint8List> _channelSnapshots = [];
  final List<Uint8List> _moduleConfigSnapshots = [];

  List<MeshtasticNode> get nodes => _nodes;
  List<BastionChatMessage> get messages =>
      _messaging?.messages ?? _archivedMessages;
  int get pendingMessageCount =>
      _messaging?.pending.length ?? _archivedPending.length;
  bool get busy => _busy;
  bool get isReady => connection.isReady;
  bool get isReconnecting => _reconnect.isRunning || _waitingForBluetooth;
  bool get bluetoothOn => _bluetoothOn;
  int? get localNodeNum => _localNodeNum;

  /// Whether radio settings can be read and written right now.
  bool get canAdminister => !_busy && connection.isReady && _admin != null;

  /// Whether the phone's location is sent to the radio for broadcasting.
  bool get sharePhoneLocation => _sharePhoneLocation;

  /// Why sharing is not running, e.g. permission denied; null when fine.
  String? get locationShareProblem => _locationShareProblem;
  DateTime? get lastPhonePositionSent => _sharer?.lastSentAt;

  Future<void> setSharePhoneLocation(bool enabled) async {
    _sharePhoneLocation = enabled;
    _locationShareProblem = null;
    notifyListeners();
    try {
      await SharedPreferencesAsync().setBool(_sharePreferenceKey, enabled);
    } catch (_) {
      // Preference storage is best effort.
    }
    if (enabled) {
      await _startSharing();
    } else {
      await _sharer?.stop();
      _sharer = null;
      notifyListeners();
    }
  }

  Future<void> _loadSharePreference() async {
    try {
      _sharePhoneLocation =
          await SharedPreferencesAsync().getBool(_sharePreferenceKey) ?? false;
      notifyListeners();
    } catch (_) {
      // Default stays off.
    }
  }

  Future<void> _startSharing() async {
    final session = _session;
    final nodeNum = _localNodeNum;
    if (!_sharePhoneLocation || session == null || nodeNum == null || !connection.isReady) {
      return;
    }
    if (_sharer?.isRunning ?? false) return;
    final sharer = BastionPhonePositionSharer(
      source: _location,
      send: session.send,
      localNodeNum: nodeNum,
    );
    _sharer = sharer;
    _locationShareProblem = await sharer.start();
    if (_locationShareProblem != null) _sharer = null;
    notifyListeners();
  }

  bool get canTraceroute =>
      !_busy && connection.isReady && _traceroute != null && !_traceroute!.isRunning;
  MeshtasticNode? get localNode {
    final num = _localNodeNum;
    if (num == null) return null;
    for (final node in _nodes) {
      if (node.num == num) return node;
    }
    return null;
  }
  List<BastionNodeRecord> get nodeDex => _nodeDex.records;
  List<double> get snrHistory => List.unmodifiable(_snrHistory);
  double? get latestSnr => _snrHistory.isEmpty ? null : _snrHistory.last;
  int get receivedTextPackets => _receivedTextPackets;
  Map<int, BastionDeviceTelemetry> get deviceTelemetry => Map.unmodifiable(_deviceTelemetry);
  List<String> get loraSettings {
    final result = <String>[];
    for (final payload in _radioConfigSnapshots) {
      try {
        final summary = BastionRadioConfigCodec.loraSummary(payload);
        if (summary != null) result.add(summary);
      } on FormatException {
        // Ignore malformed configuration frames.
      }
    }
    return List.unmodifiable(result);
  }
  List<String> get channelSettings {
    final result = <String>[];
    for (final payload in _channelSnapshots) {
      try {
        result.add(BastionRadioConfigCodec.channelSummary(payload));
      } on FormatException {
        // Ignore malformed channel frames.
      }
    }
    return List.unmodifiable(result);
  }
  /// Latest valid metadata for each channel slot, without exposing PSKs.
  List<({int index, int role, String name})> get channelMetadata {
    final bySlot = <int, ({int index, int role, String name})>{};
    for (final payload in _channelSnapshots) {
      try {
        final metadata = BastionRadioConfigCodec.channelMetadata(payload);
        bySlot[metadata.index] = metadata;
      } on FormatException {
        // Ignore malformed frames without hiding valid channel snapshots.
      }
    }
    final sorted = bySlot.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return List.unmodifiable(sorted);
  }

  int get radioConfigCount => _radioConfigSnapshots.length;
  int get channelConfigCount => _channelSnapshots.length;
  int get moduleConfigCount => _moduleConfigSnapshots.length;

  Future<void> setNodeFavorite(int num, bool value) async {
    await _nodeDex.setFavorite(num, value);
    notifyListeners();
  }

  Future<void> setNodeNote(int num, String note) async {
    await _nodeDex.setNote(num, note);
    notifyListeners();
  }

  Future<void> _loadNodeDex() async {
    await _nodeDex.load();
    notifyListeners();
  }

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
    _reconnect.cancel();
    _userDisconnected = false;
    _lastDevice = device;
    try {
      await _open(device);
    } catch (_) {
      await _background.release();
      rethrow;
    }
  }

  Future<void> _open(MeshtasticBleDevice device) async {
    if (_busy) throw StateError('Radio connection is already in progress.');
    _busy = true;
    notifyListeners();

    try {
      await _shutdownSession(resetConnection: false);
      _snrHistory.clear();
      _receivedTextPackets = 0;
      _deviceTelemetry.clear();
      _radioConfigSnapshots.clear();
      _channelSnapshots.clear();
      _moduleConfigSnapshots.clear();

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
      _linkLossSubscription =
          transport.linkLost.listen((_) => unawaited(_handleLinkLoss()));
      _waypointSubscription = session.incomingEnvelopes.listen((bytes) async {
        try {
          final envelope = pb.FromRadio.fromBuffer(bytes);
          if (envelope.hasPacket() && await _waypoints.handlePacket(envelope.packet)) {
            notifyListeners();
          }
        } catch (_) {
          // Malformed frames are handled by the other decoders.
        }
      });

      _identitySubscription = session.incomingEnvelopes.listen((bytes) {
        final envelope = MeshtasticPhoneApiCodec.decodeFromRadio(bytes);
        if (envelope.payload != null) {
          final target = switch (envelope.kind) {
            FromRadioPayloadKind.config => _radioConfigSnapshots,
            FromRadioPayloadKind.channel => _channelSnapshots,
            FromRadioPayloadKind.moduleConfig => _moduleConfigSnapshots,
            _ => null,
          };
          if (target != null) {
            target.add(Uint8List.fromList(envelope.payload!));
            notifyListeners();
          }
        }
        if (envelope.kind == FromRadioPayloadKind.packet &&
            envelope.payload != null) {
          try {
            final telemetry = BastionTelemetryCodec.decodeMeshPacket(envelope.payload!);
            if (telemetry != null) {
              _deviceTelemetry[telemetry.from] = telemetry;
              notifyListeners();
            }
            final packet = MeshtasticTextCodec.decodeMeshPacket(envelope.payload!);
            if (packet != null) {
              _receivedTextPackets++;
              if (packet.rxSnr != null && packet.rxSnr!.isFinite) {
                _snrHistory.add(packet.rxSnr!);
                if (_snrHistory.length > 60) _snrHistory.removeAt(0);
              }
              notifyListeners();
            }
          } on FormatException {
            // Non-text or malformed packets must not disrupt the BLE session.
          }
        }
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
      _nodeDexSubscription = nodeDatabase.nodeUpdates.listen((node) {
        unawaited(_nodeDex.observe(node).then((_) => notifyListeners()));
      });
      _messageSubscription = messaging.changes.listen((_) {
        _syncMessageSnapshot(messaging);
        notifyListeners();
      });
      _incomingSubscription = messaging.incoming.listen(
        _alertIncoming,
        onError: (Object _) {},
      );

      await session.connect(deviceName: device.name);
      await handshake.synchronize();
      final nodeNum = _localNodeNum;
      if (nodeNum != null && nodeNum != 0) {
        _admin = MeshtasticAdminSession(
          incoming: session.incomingEnvelopes,
          send: session.send,
          localNodeNum: nodeNum,
        );
        _traceroute = MeshtasticTraceroute(
          incoming: session.incomingEnvelopes,
          send: session.send,
          localNodeNum: nodeNum,
        );
      }
      await messaging.flush();
      unawaited(_startSharing());

      _nodes = nodeDatabase.nodes;
      _syncMessageSnapshot(messaging);
      notifyListeners();
      unawaited(_background.keepAlive(radioName: device.name, reconnecting: false));
    } catch (_) {
      await _shutdownSession(resetConnection: false);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Prepares a local owner update without sending it to the radio.
  ///
  /// This separates user input validation from the authenticated admin write.
  Uint8List prepareNodeIdentityUpdate({
    required String longName,
    required String shortName,
  }) => BastionOwnerCodec.encodeAdminSetOwner(
    longName: longName,
    shortName: shortName,
  );

  /// Observes a fresh local NodeInfo update after an authorized owner write.
  /// Call before transmitting to avoid missing a fast radio response.
  Future<MeshtasticNode> verifyNodeIdentityUpdate({
    required String longName,
    required String shortName,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final local = _localNodeNum;
    final database = _nodeDatabase;
    if (!connection.isReady || local == null || database == null) {
      throw StateError('Connected radio node database is unavailable.');
    }
    return BastionOwnerReadback.waitForMatchingUpdate(
      updates: database.nodeUpdates,
      localNodeNum: local,
      longName: longName,
      shortName: shortName,
      timeout: timeout,
    );
  }

  /// Sends a pre-encoded, authorized AdminMessage to the connected local radio.
  ///
  /// This is a low-level transport operation, not a completed settings save.
  /// Callers must obtain user confirmation, perform any firmware-required admin
  /// authentication, await the admin response, and verify a fresh readback.
  /// It deliberately does not queue admin writes while offline.
  Future<int> sendAuthorizedAdminMessage({
    required Uint8List adminMessage,
    required bool userConfirmed,
    int channel = 0,
  }) async {
    if (!userConfirmed) {
      throw StateError('Radio configuration changes require confirmation.');
    }
    if (_busy || !connection.isReady) {
      throw StateError('Radio must be connected and ready for administration.');
    }
    final session = _session;
    final nodeNum = _localNodeNum;
    if (session == null || nodeNum == null || nodeNum == 0) {
      throw StateError('Connected radio identity is not available.');
    }
    var packetId = DateTime.now().microsecondsSinceEpoch & 0xffffffff;
    if (packetId == 0) packetId = 1;
    final envelope = BastionAdminPacketCodec.toRadio(
      adminMessage: adminMessage,
      localNode: nodeNum,
      packetId: packetId,
      channel: channel,
    );
    await session.send(envelope);
    return packetId;
  }

  MeshtasticAdminSession _requireAdmin() {
    final admin = _admin;
    if (!canAdminister || admin == null) {
      throw StateError('Radio must be connected and ready to change settings.');
    }
    return admin;
  }

  Future<User> readOwner() => _requireAdmin().getOwner();

  Future<Config> readConfig(AdminMessage_ConfigType type) =>
      _requireAdmin().getConfig(type);

  Future<Channel> readChannel(int index) => _requireAdmin().getChannel(index);

  Future<ModuleConfig> readModuleConfig(AdminMessage_ModuleConfigType type) =>
      _requireAdmin().getModuleConfig(type);

  /// Writes are acknowledged by the radio; many make it reboot, after which
  /// the reconnect supervisor restores the link.
  Future<void> writeOwner(User owner) => _requireAdmin().setOwner(owner);

  Future<void> writeConfig(Config config) => _requireAdmin().setConfig(config);

  Future<void> writeChannel(Channel channel) =>
      _requireAdmin().setChannel(channel);

  Future<void> writeModuleConfig(ModuleConfig config) =>
      _requireAdmin().setModuleConfig(config);

  /// The radio's enabled channels in slot order plus its LoRa config, as
  /// shared in a channel link.
  Future<ChannelSet> readChannelSet() async {
    final admin = _requireAdmin();
    final settings = [
      for (var i = 0; i < 8; i++)
        if (await admin.getChannel(i) case final channel
            when channel.role != Channel_Role.DISABLED)
          channel.settings,
    ];
    final lora = (await admin.getConfig(AdminMessage_ConfigType.LORA_CONFIG)).lora;
    return ChannelSet(settings: settings, loraConfig: lora);
  }

  /// Applies a shared channel set.
  ///
  /// [replace] overwrites all 8 slots and the LoRa config, as the official
  /// apps do for a plain link. Otherwise the link's channels go into free
  /// slots, skipping ones already present, and LoRa is left unchanged.
  /// Returns the number of channels written.
  Future<int> applyChannelSet(ChannelSet set, {required bool replace}) async {
    final admin = _requireAdmin();
    if (replace) {
      await admin.editTransaction(() async {
        for (var i = 0; i < 8; i++) {
          await admin.setChannel(i < set.settings.length
              ? Channel(
                  index: i,
                  role: i == 0 ? Channel_Role.PRIMARY : Channel_Role.SECONDARY,
                  settings: set.settings[i],
                )
              : Channel(index: i, role: Channel_Role.DISABLED));
        }
        if (set.hasLoraConfig()) await admin.setConfig(Config(lora: set.loraConfig));
      });
      return set.settings.length;
    }
    final existing = [for (var i = 0; i < 8; i++) await admin.getChannel(i)];
    bool present(ChannelSettings s) => existing.any((c) =>
        c.role != Channel_Role.DISABLED &&
        c.settings.name == s.name &&
        _sameBytes(c.settings.psk, s.psk));
    final toAdd = set.settings.where((s) => !present(s)).toList();
    final free = existing.where((c) => c.index != 0 && c.role == Channel_Role.DISABLED).toList();
    if (toAdd.length > free.length) {
      throw StateError('Only ${free.length} free channel slots; the link has ${toAdd.length} new channels.');
    }
    if (toAdd.isEmpty) return 0;
    await admin.editTransaction(() async {
      for (var i = 0; i < toAdd.length; i++) {
        await admin.setChannel(Channel(
          index: free[i].index,
          role: Channel_Role.SECONDARY,
          settings: toAdd[i],
        ));
      }
    });
    return toAdd.length;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Asks [nodeNum] to send its position. The reply updates [nodes].
  ///
  /// Like the official apps, the request carries this radio's own position
  /// when one is known, so the other node learns where we are too.
  Future<void> requestPosition(int nodeNum) {
    final own = localNode;
    return _requestFrom(
      nodeNum,
      PortNum.POSITION_APP,
      (own != null && own.hasPosition
              ? pb.Position(
                  latitudeI: (own.latitude! * 1e7).round(),
                  longitudeI: (own.longitude! * 1e7).round(),
                )
              : pb.Position())
          .writeToBuffer(),
    );
  }

  /// Asks [nodeNum] for device telemetry. The reply updates [deviceTelemetry].
  Future<void> requestTelemetry(int nodeNum) => _requestFrom(
        nodeNum,
        PortNum.TELEMETRY_APP,
        Telemetry(deviceMetrics: DeviceMetrics()).writeToBuffer(),
      );

  Future<void> _requestFrom(int nodeNum, PortNum port, List<int> payload) async {
    final session = _session;
    if (_busy || !connection.isReady || session == null) {
      throw StateError('Radio must be connected and ready.');
    }
    if (nodeNum == _localNodeNum) {
      throw ArgumentError.value(nodeNum, 'nodeNum', 'is this radio');
    }
    var id = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    if (id == 0) id = 1;
    await session.send(pb.ToRadio(
      packet: pb.MeshPacket(
        to: nodeNum,
        id: id,
        wantAck: true,
        decoded: pb.Data(portnum: port, payload: payload, wantResponse: true),
      ),
    ).writeToBuffer());
  }

  List<MeshWaypoint> get waypoints => _waypoints.waypoints;

  /// Broadcasts [waypoint] on [channel] and keeps it locally.
  Future<void> sendWaypoint(MeshWaypoint waypoint, {int channel = 0}) async {
    final session = _session;
    if (_busy || !connection.isReady || session == null) {
      throw StateError('Radio must be connected and ready.');
    }
    await session.send(BastionWaypointStore.encode(waypoint, channel: channel));
    await _waypoints.apply(waypoint);
    notifyListeners();
  }

  /// Whether this radio may change or delete [waypoint].
  bool canEditWaypoint(MeshWaypoint waypoint) =>
      waypoint.lockedTo == 0 || waypoint.lockedTo == _localNodeNum;

  /// Removes [waypoint] for everyone by broadcasting it as expired.
  Future<void> deleteWaypoint(MeshWaypoint waypoint, {int channel = 0}) async {
    if (!canEditWaypoint(waypoint)) {
      throw StateError('This waypoint is locked to another node.');
    }
    await sendWaypoint(BastionWaypointStore.deletion(waypoint), channel: channel);
  }

  /// Traces the mesh route to [nodeNum]. Only one trace runs at a time.
  Future<TracerouteResult> traceroute(int nodeNum) async {
    final traceroute = _traceroute;
    if (!canTraceroute || traceroute == null) {
      throw StateError('Radio must be ready and idle to run a traceroute.');
    }
    final result = traceroute.trace(nodeNum);
    notifyListeners();
    try {
      return await result;
    } finally {
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

  /// Notifies about a message that arrives while the app is backgrounded.
  void _alertIncoming(MeshtasticTextMessage message) {
    if (_inForeground) return;
    String sender = '!${message.from.toRadixString(16).padLeft(8, '0')}';
    for (final node in _nodes) {
      if (node.num == message.from) sender = node.displayName;
    }
    unawaited(_alerts.show(
      packetId: message.packetId,
      sender: sender,
      text: message.text,
      isDirect: !message.isBroadcast,
      channel: message.channel,
    ));
  }

  @visibleForTesting
  set inForeground(bool value) => _inForeground = value;

  /// Starts link recovery for [device] as if its link had just dropped.
  @visibleForTesting
  Future<void> recoverLinkForTest(MeshtasticBleDevice device) {
    _lastDevice = device;
    _userDisconnected = false;
    return _recoverLink(device);
  }

  @visibleForTesting
  void alertIncomingForTest(MeshtasticTextMessage message) => _alertIncoming(message);

  /// Tears down a dropped session and retries the last radio with backoff.
  Future<void> _handleLinkLoss() async {
    final device = _lastDevice;
    if (_busy || _userDisconnected || device == null) return;
    await _shutdownSession(resetConnection: false);
    await _recoverLink(device);
  }

  void _handleBluetoothChange(bool on) {
    _bluetoothOn = on;
    final device = _lastDevice;
    if (on && _waitingForBluetooth && device != null && !_userDisconnected &&
        !_busy && _session == null && !_reconnect.isRunning) {
      unawaited(_recoverLink(device));
    }
    notifyListeners();
  }

  Future<void> _recoverLink(MeshtasticBleDevice device) async {
    // Checked here rather than at startup: the change stream can miss a
    // state flip made while the app was suspended.
    _bluetoothOn = await _bluetooth.isOn();
    if (_userDisconnected) return;
    if (!_bluetoothOn) {
      _waitingForBluetooth = true;
      unawaited(_background.keepAlive(radioName: device.name, reconnecting: true));
      connection.fail(StateError(
        'Bluetooth is off. Bastion will reconnect to ${device.name} when it is turned back on.',
      ));
      notifyListeners();
      return;
    }
    _waitingForBluetooth = false;
    connection.beginConnect(device.name);
    unawaited(_background.keepAlive(radioName: device.name, reconnecting: true));
    final recovery = _reconnect.recover();
    notifyListeners();
    final recovered = await recovery;
    if (!recovered && !_bluetoothOn && !_userDisconnected) {
      // Bluetooth went off mid-recovery; wait for it instead of giving up.
      await _recoverLink(device);
      return;
    }
    if (!recovered && !_userDisconnected && !_busy && _session == null) {
      unawaited(_background.release());
      connection.fail(StateError(
        'Radio link lost; reconnect gave up after ${_reconnect.attempts} '
        'attempts. Last error: ${_reconnect.lastError}',
      ));
    }
  }

  Future<void> _reconnectLastDevice() async {
    final device = _lastDevice;
    if (device == null) throw StateError('No radio to reconnect.');
    await _open(device);
    // The user may have pressed disconnect while this attempt was in flight.
    if (_userDisconnected) await _shutdownSession(resetConnection: true);
  }

  Future<void> disconnect() async {
    _userDisconnected = true;
    _waitingForBluetooth = false;
    _reconnect.cancel();
    unawaited(_background.release());
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
    await _nodeDexSubscription?.cancel();
    _nodeDexSubscription = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    await _identitySubscription?.cancel();
    _identitySubscription = null;
    await _linkLossSubscription?.cancel();
    _linkLossSubscription = null;
    await _waypointSubscription?.cancel();
    _waypointSubscription = null;
    await _sharer?.stop();
    _sharer = null;
    await _admin?.dispose();
    _admin = null;
    await _traceroute?.dispose();
    _traceroute = null;
    await _handshake?.dispose();
    _handshake = null;
    await _messaging?.dispose();
    _messaging = null;
    await _nodeDatabase?.dispose();
    _nodeDatabase = null;
    await _session?.dispose();
    _session = null;
    _nodes = const [];
    _deviceTelemetry.clear();
    _radioConfigSnapshots.clear();
    _channelSnapshots.clear();
    _moduleConfigSnapshots.clear();
    _localNodeNum = null;
    if (resetConnection) connection.disconnect();
  }

  void _relayConnectionChange() => notifyListeners();

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_bluetoothSubscription.cancel());
    _userDisconnected = true;
    _reconnect.cancel();
    unawaited(_background.release());
    connection.removeListener(_relayConnectionChange);
    unawaited(_shutdownSession(resetConnection: true));
    super.dispose();
  }
}
