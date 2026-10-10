import 'dart:async';

import 'meshtastic_node_database.dart';

/// Waits for a *new* node update matching a requested local owner identity.
/// A previously cached value is not evidence that an admin write succeeded.
abstract final class BastionOwnerReadback {
  static Future<MeshtasticNode> waitForMatchingUpdate({
    required Stream<MeshtasticNode> updates,
    required int localNodeNum,
    required String longName,
    required String shortName,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (localNodeNum <= 0) throw ArgumentError.value(localNodeNum, 'localNodeNum');
    return updates.firstWhere((node) =>
      node.num == localNodeNum &&
      node.longName == longName.trim() &&
      node.shortName == shortName.trim(),
    ).timeout(timeout, onTimeout: () =>
      throw TimeoutException('Radio did not report the requested node names.', timeout));
  }
}
