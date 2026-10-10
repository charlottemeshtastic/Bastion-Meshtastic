import 'dart:async';
import 'dart:typed_data';

import 'package:bastion/generated/meshtastic/admin.pb.dart';
import 'package:bastion/generated/meshtastic/config.pb.dart';
import 'package:bastion/generated/meshtastic/mesh.pb.dart';
import 'package:bastion/generated/meshtastic/portnums.pbenum.dart';
import 'package:bastion/services/meshtastic_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';

const localNode = 0x1234;

/// Answers admin packets the way local firmware 2.5+ does.
class FakeAdminRadio {
  FakeAdminRadio({this.passkey = const [9, 9, 9, 9]});

  final List<int> passkey;

  /// Key the radio accepts on writes; differs from [passkey] after rotation.
  late List<int> acceptedPasskey = passkey;
  final incoming = StreamController<Uint8List>.broadcast();
  final received = <AdminMessage>[];
  Config lora = Config(
    lora: Config_LoRaConfig(region: Config_LoRaConfig_RegionCode.US, hopLimit: 3),
  );
  bool silent = false;

  Future<void> send(Uint8List bytes) async {
    final packet = ToRadio.fromBuffer(bytes).packet;
    expect(packet.to, localNode);
    expect(packet.decoded.portnum, PortNum.ADMIN_APP);
    final admin = AdminMessage.fromBuffer(packet.decoded.payload);
    received.add(admin);
    if (silent) return;
    scheduleMicrotask(() => _answer(packet.id, admin));
  }

  void _answer(int id, AdminMessage admin) {
    switch (admin.whichPayloadVariant()) {
      case AdminMessage_PayloadVariant.getOwnerRequest:
        _reply(id, AdminMessage(
          getOwnerResponse: User(longName: 'Trail', shortName: 'TR'),
          sessionPasskey: passkey,
        ));
      case AdminMessage_PayloadVariant.getConfigRequest:
        _reply(id, AdminMessage(getConfigResponse: lora, sessionPasskey: passkey));
      case AdminMessage_PayloadVariant.setConfig:
        if (!_listEquals(admin.sessionPasskey, acceptedPasskey)) {
          _routing(id, Routing_Error.ADMIN_BAD_SESSION_KEY);
        } else {
          lora = admin.setConfig;
          _routing(id, Routing_Error.NONE);
        }
      default:
        _routing(id, Routing_Error.NONE);
    }
  }

  void _reply(int requestId, AdminMessage admin) => _emit(Data(
        portnum: PortNum.ADMIN_APP,
        payload: admin.writeToBuffer(),
        requestId: requestId,
      ));

  void _routing(int requestId, Routing_Error error) => _emit(Data(
        portnum: PortNum.ROUTING_APP,
        payload: Routing(errorReason: error).writeToBuffer(),
        requestId: requestId,
      ));

  void _emit(Data data) => incoming.add(FromRadio(
        packet: MeshPacket(from: localNode, to: localNode, decoded: data),
      ).writeToBuffer());

  static bool _listEquals(List<int> a, List<int> b) =>
      a.length == b.length && Iterable.generate(a.length).every((i) => a[i] == b[i]);
}

MeshtasticAdminSession sessionFor(FakeAdminRadio radio, {Duration? timeout}) =>
    MeshtasticAdminSession(
      incoming: radio.incoming.stream,
      send: radio.send,
      localNodeNum: localNode,
      timeout: timeout ?? const Duration(seconds: 2),
    );

void main() {
  test('reads config and captures the session passkey', () async {
    final radio = FakeAdminRadio();
    final admin = sessionFor(radio);
    final config = await admin.getConfig(AdminMessage_ConfigType.LORA_CONFIG);
    expect(config.lora.region, Config_LoRaConfig_RegionCode.US);
    expect(admin.hasFreshPasskey, isTrue);
    await admin.dispose();
  });

  test('write fetches a passkey first and attaches it', () async {
    final radio = FakeAdminRadio();
    final admin = sessionFor(radio);
    await admin.setConfig(Config(
      lora: Config_LoRaConfig(region: Config_LoRaConfig_RegionCode.EU_868, hopLimit: 5),
    ));
    expect(radio.received.first.whichPayloadVariant(),
        AdminMessage_PayloadVariant.getOwnerRequest);
    expect(radio.received.last.sessionPasskey, [9, 9, 9, 9]);
    expect(radio.lora.lora.region, Config_LoRaConfig_RegionCode.EU_868);
    expect(radio.lora.lora.hopLimit, 5);
    await admin.dispose();
  });

  test('negative acknowledgement fails the write and drops the passkey', () async {
    final radio = FakeAdminRadio()..acceptedPasskey = const [1, 2, 3, 4];
    final admin = sessionFor(radio);
    await expectLater(
      admin.setConfig(Config(lora: Config_LoRaConfig(hopLimit: 4))),
      throwsA(isA<MeshtasticAdminException>().having(
          (e) => e.message, 'message', contains('ADMIN_BAD_SESSION_KEY'))),
    );
    expect(admin.hasFreshPasskey, isFalse);
    expect(radio.lora.lora.hopLimit, 3);
    await admin.dispose();
  });

  test('times out when the radio does not answer', () async {
    final radio = FakeAdminRadio()..silent = true;
    final admin = sessionFor(radio, timeout: const Duration(milliseconds: 50));
    await expectLater(
      admin.getOwner(),
      throwsA(isA<MeshtasticAdminException>()),
    );
    await admin.dispose();
  });

  test('ignores responses to other requests and malformed frames', () async {
    final radio = FakeAdminRadio();
    final admin = sessionFor(radio);
    radio.incoming.add(Uint8List.fromList([0xff, 0xff, 0xff]));
    radio._reply(424242, AdminMessage(getOwnerResponse: User(longName: 'Other')));
    final owner = await admin.getOwner();
    expect(owner.longName, 'Trail');
    await admin.dispose();
  });

  test('editTransaction wraps writes in begin and commit', () async {
    final radio = FakeAdminRadio();
    final admin = sessionFor(radio);
    await admin.editTransaction(() => admin.setConfig(
          Config(lora: Config_LoRaConfig(hopLimit: 2)),
        ));
    final kinds = radio.received.map((m) => m.whichPayloadVariant()).toList();
    expect(kinds, [
      AdminMessage_PayloadVariant.getOwnerRequest,
      AdminMessage_PayloadVariant.beginEditSettings,
      AdminMessage_PayloadVariant.setConfig,
      AdminMessage_PayloadVariant.commitEditSettings,
    ]);
    await admin.dispose();
  });
}
