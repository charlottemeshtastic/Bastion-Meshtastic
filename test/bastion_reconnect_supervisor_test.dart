import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_reconnect_supervisor.dart';

void main() {
  test('retries transient failures with bounded exponential delays', () async {
    var calls = 0;
    final delays = <Duration>[];
    final supervisor = BastionReconnectSupervisor(
      reconnect: () async {
        calls++;
        if (calls < 3) throw StateError('radio unavailable');
      },
      mayReconnect: () => true,
      wait: (delay) async { delays.add(delay); },
    );
    expect(await supervisor.recover(), isTrue);
    expect(calls, 3);
    expect(delays, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
    expect(supervisor.lastError, isNull);
  });

  test('manual cancellation prevents a pending reconnect', () async {
    final gate = Completer<void>();
    var calls = 0;
    final supervisor = BastionReconnectSupervisor(
      reconnect: () async { calls++; },
      mayReconnect: () => true,
      wait: (_) => gate.future,
    );
    final result = supervisor.recover();
    supervisor.cancel();
    gate.complete();
    expect(await result, isFalse);
    expect(calls, 0);
  });

  test('disabled Bluetooth prevents reconnect attempts', () async {
    var calls = 0;
    final supervisor = BastionReconnectSupervisor(
      reconnect: () async { calls++; },
      mayReconnect: () => false,
      wait: (_) async {},
    );
    expect(await supervisor.recover(), isFalse);
    expect(calls, 0);
  });

  test('limits retries and preserves last failure', () async {
    var calls = 0;
    final supervisor = BastionReconnectSupervisor(
      reconnect: () async {
        calls++;
        throw StateError('offline');
      },
      mayReconnect: () => true,
      wait: (_) async {},
      maxAttempts: 2,
    );
    expect(await supervisor.recover(), isFalse);
    expect(calls, 2);
    expect(supervisor.lastError, isA<StateError>());
  });
}
