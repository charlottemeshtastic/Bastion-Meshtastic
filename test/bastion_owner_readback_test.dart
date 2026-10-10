import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_owner_readback.dart';
import 'package:bastion/services/meshtastic_node_database.dart';

void main() {
  test('ignores other nodes and stale names until local node matches', () async {
    final controller = StreamController<MeshtasticNode>.broadcast();
    final result = BastionOwnerReadback.waitForMatchingUpdate(
      updates: controller.stream, localNodeNum: 42,
      longName: 'Bastion', shortName: 'BCS',
    );
    controller.add(const MeshtasticNode(num: 7, longName: 'Bastion', shortName: 'BCS'));
    controller.add(const MeshtasticNode(num: 42, longName: 'Old', shortName: 'OLD'));
    controller.add(const MeshtasticNode(num: 42, longName: 'Bastion', shortName: 'BCS'));
    expect((await result).num, 42);
    await controller.close();
  });

  test('times out without fresh matching readback', () async {
    final controller = StreamController<MeshtasticNode>.broadcast();
    await expectLater(BastionOwnerReadback.waitForMatchingUpdate(
      updates: controller.stream, localNodeNum: 42,
      longName: 'Bastion', shortName: 'BCS',
      timeout: const Duration(milliseconds: 10),
    ), throwsA(isA<TimeoutException>()));
    await controller.close();
  });
}
