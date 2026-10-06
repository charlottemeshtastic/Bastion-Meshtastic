import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/models/mesh_node.dart';
import 'package:bastion_meshtastic/services/node_archive.dart';
import 'package:bastion_meshtastic/services/meshtastic/radio_session.dart';
import 'package:bastion_meshtastic/screens/map/mesh_map_page.dart';
import 'package:bastion_meshtastic/screens/tools/field_dashboard_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('offline map renders saved markers and opens node history', (
    tester,
  ) async {
    final archive = NodeArchive();
    await archive.load();
    archive.seed(42, [
      MeshNode(
        number: 7,
        name: 'Ridge',
        latitude: 35.32,
        longitude: -83.8,
        positionTime: DateTime.utc(2026, 10, 5),
      ),
    ]);
    final session = RadioSession();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeshMapPage(session: session, archive: archive),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TileLayer), findsNothing);
    expect(find.byType(MarkerLayer), findsOneWidget);
    await tester.tap(find.text('Ridge').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('NODE HISTORY'));
    await tester.pumpAndSettle();
    expect(find.text('RECEIVED TELEMETRY'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await archive.saved;
    archive.dispose();
    session.dispose();
  });

  testWidgets(
    'field dashboard distinguishes external power and unknown battery',
    (tester) async {
      final archive = NodeArchive();
      await archive.load();
      archive.seed(42, [
        const MeshNode(number: 7, name: 'Low node', battery: 12),
        const MeshNode(number: 8, name: 'Powered node', powered: true),
        const MeshNode(number: 9, name: 'Unknown node'),
      ]);
      final session = RadioSession();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FieldDashboardPage(session: session, archive: archive),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 below 20%'), findsOneWidget);
      expect(find.text('Powered'), findsOneWidget);
      await tester.tap(find.text('Below 20% battery'));
      await tester.pumpAndSettle();
      expect(find.text('Low node'), findsOneWidget);
      expect(find.text('Powered node'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await archive.saved;
      archive.dispose();
      session.dispose();
    },
  );
}
