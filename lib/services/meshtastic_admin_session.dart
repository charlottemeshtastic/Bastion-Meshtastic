import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';

import '../generated/meshtastic/admin.pb.dart';
import '../generated/meshtastic/channel.pb.dart';
import '../generated/meshtastic/config.pb.dart';
import '../generated/meshtastic/mesh.pb.dart';
import '../generated/meshtastic/module_config.pb.dart';
import '../generated/meshtastic/portnums.pbenum.dart';

class MeshtasticAdminException implements Exception {
  MeshtasticAdminException(this.message);

  final String message;

  @override
  String toString() => 'MeshtasticAdminException: $message';
}

/// Request/response admin channel to the locally connected radio.
///
/// Reads return the radio's answer. Writes wait for the radio's routing ACK
/// and fail on a negative acknowledgement or timeout. Firmware 2.5+ rejects
/// writes without the session passkey it returns on any admin read, so every
/// write first makes sure a fresh passkey is held.
///
/// Many config writes make the radio reboot; the BLE link then drops and the
/// coordinator's reconnect supervisor takes over.
class MeshtasticAdminSession {
  MeshtasticAdminSession({
    required Stream<Uint8List> incoming,
    required Future<void> Function(Uint8List toRadio) send,
    required this.localNodeNum,
    this.timeout = const Duration(seconds: 15),
    DateTime Function()? clock,
    Random? random,
  })  : _send = send,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure() {
    _subscription = incoming.listen(_handleEnvelope);
  }

  /// Firmware expires the passkey after 300 s; renew early.
  static const passkeyLifetime = Duration(seconds: 240);

  final int localNodeNum;
  final Duration timeout;
  final Future<void> Function(Uint8List) _send;
  final DateTime Function() _clock;
  final Random _random;
  final Map<int, _PendingRequest> _pending = {};
  late final StreamSubscription<Uint8List> _subscription;

  List<int>? _passkey;
  DateTime? _passkeyReceivedAt;

  bool get hasFreshPasskey =>
      _passkey != null &&
      _clock().difference(_passkeyReceivedAt!) < passkeyLifetime;

  Future<User> getOwner() async =>
      (await _request(AdminMessage(getOwnerRequest: true), 'owner'))
          .getOwnerResponse;

  Future<Config> getConfig(AdminMessage_ConfigType type) async =>
      (await _request(AdminMessage(getConfigRequest: type), type.name))
          .getConfigResponse;

  Future<ModuleConfig> getModuleConfig(
    AdminMessage_ModuleConfigType type,
  ) async =>
      (await _request(AdminMessage(getModuleConfigRequest: type), type.name))
          .getModuleConfigResponse;

  /// [index] is the 0-based channel slot; the protocol sends index + 1.
  Future<Channel> getChannel(int index) async {
    if (index < 0 || index > 7) throw RangeError.range(index, 0, 7, 'index');
    return (await _request(
      AdminMessage(getChannelRequest: index + 1),
      'channel $index',
    ))
        .getChannelResponse;
  }

  Future<void> setOwner(User owner) =>
      _write(AdminMessage(setOwner: owner), 'owner');

  Future<void> setConfig(Config config) =>
      _write(AdminMessage(setConfig: config), config.whichPayloadVariant().name);

  Future<void> setModuleConfig(ModuleConfig config) => _write(
        AdminMessage(setModuleConfig: config),
        config.whichPayloadVariant().name,
      );

  Future<void> setChannel(Channel channel) =>
      _write(AdminMessage(setChannel: channel), 'channel ${channel.index}');

  /// Groups several writes so the radio saves and reboots once at the end.
  Future<void> editTransaction(Future<void> Function() edits) async {
    await _write(AdminMessage(beginEditSettings: true), 'begin edit');
    await edits();
    await _write(AdminMessage(commitEditSettings: true), 'commit edit');
  }

  Future<void> ensureAuthorized() async {
    if (hasFreshPasskey) return;
    await getOwner();
    // Firmware older than 2.5 sends no passkey and does not require one.
  }

  Future<void> _write(AdminMessage message, String what) async {
    await ensureAuthorized();
    final passkey = _passkey;
    if (passkey != null) message.sessionPasskey = passkey;
    await _exchange(message, what, expectsResponse: false);
  }

  Future<AdminMessage> _request(AdminMessage message, String what) async =>
      (await _exchange(message, what, expectsResponse: true))!;

  Future<AdminMessage?> _exchange(
    AdminMessage message,
    String what, {
    required bool expectsResponse,
  }) async {
    final id = _nextPacketId();
    final pending = _PendingRequest(expectsResponse);
    _pending[id] = pending;
    final envelope = ToRadio(
      packet: MeshPacket(
        to: localNodeNum,
        id: id,
        wantAck: true,
        decoded: Data(
          portnum: PortNum.ADMIN_APP,
          payload: message.writeToBuffer(),
          wantResponse: expectsResponse,
        ),
      ),
    );
    try {
      await _send(envelope.writeToBuffer());
      return await pending.completer.future.timeout(
        timeout,
        onTimeout: () => throw MeshtasticAdminException(
          'Radio did not answer $what within ${timeout.inSeconds} s.',
        ),
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _handleEnvelope(Uint8List bytes) {
    final FromRadio envelope;
    try {
      envelope = FromRadio.fromBuffer(bytes);
    } on InvalidProtocolBufferException {
      return;
    }
    if (!envelope.hasPacket() || !envelope.packet.hasDecoded()) return;
    final data = envelope.packet.decoded;
    final pending = _pending[data.requestId];

    if (data.portnum == PortNum.ADMIN_APP) {
      final AdminMessage admin;
      try {
        admin = AdminMessage.fromBuffer(data.payload);
      } on InvalidProtocolBufferException {
        return;
      }
      if (admin.sessionPasskey.isNotEmpty) {
        _passkey = List.unmodifiable(admin.sessionPasskey);
        _passkeyReceivedAt = _clock();
      }
      if (pending != null && pending.expectsResponse) {
        pending.complete(admin);
      }
    } else if (data.portnum == PortNum.ROUTING_APP && pending != null) {
      final Routing routing;
      try {
        routing = Routing.fromBuffer(data.payload);
      } on InvalidProtocolBufferException {
        return;
      }
      if (routing.whichVariant() != Routing_Variant.errorReason) return;
      if (routing.errorReason != Routing_Error.NONE) {
        if (routing.errorReason == Routing_Error.ADMIN_BAD_SESSION_KEY) {
          _passkey = null;
        }
        pending.fail(MeshtasticAdminException(
          'Radio rejected the request: ${routing.errorReason.name}.',
        ));
      } else if (!pending.expectsResponse) {
        pending.complete(null);
      }
    }
  }

  int _nextPacketId() {
    int id;
    do {
      id = _random.nextInt(0x7fffffff) + 1;
    } while (_pending.containsKey(id));
    return id;
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    for (final pending in _pending.values) {
      pending.fail(MeshtasticAdminException('Admin session closed.'));
    }
    _pending.clear();
  }
}

class _PendingRequest {
  _PendingRequest(this.expectsResponse);

  final bool expectsResponse;
  final Completer<AdminMessage?> completer = Completer<AdminMessage?>();

  void complete(AdminMessage? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  void fail(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }
}
