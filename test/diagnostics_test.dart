import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/services/diagnostics.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'package:bastion_meshtastic/generated/meshtastic/channel.pb.dart';

void main() {
  test(
    'diagnostics contains useful status and omits channel keys and names',
    () {
      final session = RadioSession();
      session.localNode = 42;
      session.firmware = '2.7.test';
      session.channels[0] = Channel(
        index: 0,
        role: Channel_Role.PRIMARY,
        settings: ChannelSettings(
          name: 'Private channel name',
          psk: utf8.encode('secret-key'),
        ),
      );
      final text = radioDiagnostics(session, now: DateTime.utc(2026, 10, 5));
      expect(text, contains('Local node: !0000002a'));
      expect(text, contains('Firmware: 2.7.test'));
      expect(text, contains('Enabled channels: 1'));
      expect(text, isNot(contains('secret-key')));
      expect(text, isNot(contains('Private channel name')));
      expect(text, isNot(contains(base64Encode(utf8.encode('secret-key')))));
      session.dispose();
    },
  );
}
