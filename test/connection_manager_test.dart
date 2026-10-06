import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:bastion_meshtastic/services/connection/connection_manager.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'radio_session_test.dart' show FakeTransport;

class FakeConnectionBackend implements ConnectionServiceBackend {
  final events = StreamController<void>.broadcast();
  bool active = false;
  bool allowed = true;
  bool confirms = true;
  int starts = 0;
  int stopsCount = 0;
  @override
  bool get supported => true;
  @override
  Stream<void> get stops => events.stream;
  @override
  Future<bool> requestNotifications() async => allowed;
  @override
  Future<bool> start(String status) async {
    starts++;
    active = confirms;
    return active;
  }

  @override
  Future<void> stop() async {
    final wasActive = active;
    active = false;
    stopsCount++;
    if (wasActive) {
      events.add(null);
    }
  }

  @override
  Future<bool> running() async => active;
  @override
  Future<bool> heartbeat() async => active;
}

class AutoTransport extends FakeTransport {
  AutoTransport({this.radio = 42});
  final int radio;
  @override
  Future<void> write(List<int> bytes) async {
    await super.write(bytes);
    final f = pb.ToRadio.fromBuffer(bytes);
    if (f.hasWantConfigId()) {
      emit(pb.FromRadio(myInfo: pb.MyNodeInfo(myNodeNum: radio)));
      emit(pb.FromRadio(configCompleteId: f.wantConfigId));
    }
  }
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Expected recovery state did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late RadioSession session;
  late ConnectionManager manager;
  late FakeConnectionBackend backend;
  late List<AutoTransport> transports;
  setUp(() {
    session = RadioSession(
      nonce: () => 123,
      configTimeout: const Duration(milliseconds: 50),
    );
    backend = FakeConnectionBackend();
    transports = [];
    manager = ConnectionManager(
      session,
      backend: backend,
      retryDelays: const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
      ],
    );
  });
  tearDown(() async {
    await manager.stop();
    manager.dispose();
    await session.disconnect();
    session.dispose();
    for (final t in transports) {
      await t.finish();
    }
    await backend.events.close();
  });
  AutoTransport good() {
    final t = AutoTransport();
    transports.add(t);
    return t;
  }

  test(
    'default foreground pause disconnects and screen-off lease preserves radio',
    () async {
      await manager.connect(good);
      expect(session.status, RadioStatus.ready);
      expect(manager.autoReconnect, isFalse);
      expect(manager.screenOff, isFalse);
      await manager.onForeground(false);
      expect(session.status, RadioStatus.disconnected);
      await manager.onForeground(true);
      await manager.connect(good);
      await manager.setScreenOff(true);
      expect(manager.screenOff, isTrue);
      await manager.onForeground(false);
      expect(session.status, RadioStatus.ready);
      await manager.stop();
      expect(session.status, RadioStatus.disconnected);
      expect(backend.active, isFalse);
    },
  );
  test(
    'notification refusal or unconfirmed service never enables background',
    () async {
      await manager.connect(good);
      backend.allowed = false;
      await manager.setScreenOff(true);
      expect(manager.screenOff, isFalse);
      expect(backend.starts, 0);
      backend.allowed = true;
      backend.confirms = false;
      await manager.setScreenOff(true);
      expect(manager.screenOff, isFalse);
      expect(manager.error, contains('did not confirm'));
    },
  );
  test('native STOP disarms recovery and disconnects', () async {
    await manager.connect(good);
    manager.setAutoReconnect(true);
    await manager.setScreenOff(true);
    backend.active = false;
    backend.events.add(null);
    await until(
      () =>
          session.status == RadioStatus.disconnected && !manager.autoReconnect,
    );
    expect(manager.screenOff, isFalse);
    expect(manager.autoReconnect, isFalse);
    expect(session.status, RadioStatus.disconnected);
  });
  test(
    'drop retries only selected transport and verifies original identity',
    () async {
      await manager.connect(good);
      manager.setAutoReconnect(true);
      transports.first.lost.add(null);
      await until(
        () => transports.length == 2 && session.status == RadioStatus.ready,
      );
      expect(transports, hasLength(2));
      expect(session.status, RadioStatus.ready);
      expect(manager.attempts, 0);
    },
  );
  test('manual STOP cancels scheduled retry', () async {
    await manager.connect(good);
    manager.setAutoReconnect(true);
    transports.first.lost.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await manager.stop();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(transports, hasLength(1));
    expect(manager.retryPending, isFalse);
  });
  test('failed recovery is bounded and stops service after limit', () async {
    var first = true;
    AutoTransport factory() {
      final t = good();
      t.failOpen = !first;
      first = false;
      return t;
    }

    await manager.connect(factory);
    manager.setAutoReconnect(true);
    await manager.setScreenOff(true);
    transports.first.lost.add(null);
    await until(
      () => transports.length == 3 && !manager.autoReconnect && !backend.active,
    );
    expect(transports, hasLength(3));
    expect(manager.autoReconnect, isFalse);
    expect(manager.screenOff, isFalse);
    expect(backend.active, isFalse);
    expect(manager.error, contains('Recovery exhausted'));
  });
  test(
    'changed radio identity disarms instead of silently switching',
    () async {
      var number = 42;
      AutoTransport factory() {
        final t = AutoTransport(radio: number);
        transports.add(t);
        return t;
      }

      await manager.connect(factory);
      manager.setAutoReconnect(true);
      number = 99;
      transports.first.lost.add(null);
      await until(
        () =>
            transports.length == 2 &&
            !manager.autoReconnect &&
            session.status == RadioStatus.disconnected,
      );
      expect(manager.autoReconnect, isFalse);
      expect(session.status, RadioStatus.disconnected);
      expect(manager.error, contains('identity changed'));
    },
  );
}
