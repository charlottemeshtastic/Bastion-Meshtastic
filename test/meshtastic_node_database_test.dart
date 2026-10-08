import 'dart:typed_data';

import 'package:bastion/services/meshtastic_node_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes NodeInfo identity fields used by Bastion node list', () {
    final user = <int>[
      0x0a, 0x09, ...'!1234abcd'.codeUnits,
      0x12, 0x0b, ...'Ridge Relay'.codeUnits,
      0x1a, 0x02, ...'RR'.codeUnits,
      0x28, 0x09,
    ];
    final nodeInfo = Uint8List.fromList([
      0x08, 0xac, 0xd7, 0xad, 0x0b,
      0x12, user.length, ...user,
    ]);

    final node = MeshtasticNodeInfoCodec.decode(nodeInfo);
    expect(node.num, 23817132);
    expect(node.id, '!1234abcd');
    expect(node.longName, 'Ridge Relay');
    expect(node.shortName, 'RR');
    expect(node.hardwareModel, 9);
    expect(node.displayName, 'Ridge Relay');
  });

  test('requires a node number', () {
    expect(
      () => MeshtasticNodeInfoCodec.decode(Uint8List.fromList([0x12, 0x00])),
      throwsA(isA<FormatException>()),
    );
  });
}
