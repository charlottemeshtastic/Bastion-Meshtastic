import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/services/connection/connection_manager.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'package:bastion_meshtastic/screens/nodes/connection_panel.dart';
import 'connection_manager_test.dart' show AutoTransport, FakeConnectionBackend;

void main() {
  testWidgets('connection controls opt in and STOP disables the lease', (
    tester,
  ) async {
    final session = RadioSession(nonce: () => 123);
    final backend = FakeConnectionBackend();
    final manager = ConnectionManager(session, backend: backend);
    final transport = AutoTransport();
    await tester.runAsync(() => manager.connect(() => transport));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(children: [ConnectionPanel(manager: manager)]),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('reconnect-toggle')));
    await tester.pumpAndSettle();
    expect(manager.autoReconnect, isTrue);
    await tester.tap(find.byKey(const Key('screen-off-toggle')));
    await tester.pumpAndSettle();
    expect(manager.screenOff, isTrue);
    expect(backend.active, isTrue);
    await tester.tap(find.byKey(const Key('screen-off-toggle')));
    await tester.pumpAndSettle();
    expect(manager.screenOff, isFalse);
    expect(manager.autoReconnect, isFalse);
    expect(session.status, RadioStatus.disconnected);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await manager.stop();
      manager.dispose();
      await session.disconnect();
      session.dispose();
      await transport.finish();
      await backend.events.close();
    });
  });
}
