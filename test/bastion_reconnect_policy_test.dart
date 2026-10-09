import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_reconnect_policy.dart';

void main() {
  test('backs off retries with a bounded delay', () {
    expect(BastionReconnectPolicy.delayForAttempt(0), const Duration(seconds: 1));
    expect(BastionReconnectPolicy.delayForAttempt(3), const Duration(seconds: 8));
    expect(BastionReconnectPolicy.delayForAttempt(20), const Duration(seconds: 30));
  });
  test('never reconnects after manual disconnect or disabled bluetooth', () {
    expect(BastionReconnectPolicy.shouldReconnect(userDisconnected: true, bluetoothEnabled: true), isFalse);
    expect(BastionReconnectPolicy.shouldReconnect(userDisconnected: false, bluetoothEnabled: false), isFalse);
    expect(BastionReconnectPolicy.shouldReconnect(userDisconnected: false, bluetoothEnabled: true), isTrue);
  });
}
