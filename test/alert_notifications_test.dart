import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/services/alert_notifications.dart';
import 'package:bastion_meshtastic/services/automations/automation_engine.dart';
import 'package:bastion_meshtastic/services/automations/automation_controller.dart';
import 'package:bastion_meshtastic/models/mesh_node.dart';

class FakeAlerts implements AlertNotificationBackend {
  bool permission = true;
  bool failShow = false;
  int requests = 0;
  final shown = <String>[];
  @override
  bool get supported => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> allowed() async => permission;
  @override
  Future<bool> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Future<void> show(int id, String title, String body) async {
    if (failShow) {
      throw StateError('OS failure');
    }
    shown.add(body);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'notification opt-in persists and permission denial never enables it',
    () async {
      final backend = FakeAlerts()..permission = false;
      final notifications = AlertNotifications(backend: backend);
      await notifications.load();
      expect(notifications.enabled, false);
      await notifications.setEnabled(true);
      expect(notifications.enabled, false);
      expect(notifications.error, isNotNull);
      backend.permission = true;
      await notifications.setEnabled(true);
      expect(notifications.enabled, true);
      final restored = AlertNotifications(backend: backend);
      await restored.load();
      expect(restored.enabled, true);
      await restored.setEnabled(false);
      await restored.test();
      expect(backend.shown, isEmpty);
      restored.dispose();
      notifications.dispose();
    },
  );

  test(
    'new live events notify; restored history and simulation do not replay',
    () async {
      final backend = FakeAlerts();
      final notifications = AlertNotifications(backend: backend);
      await notifications.load();
      await notifications.setEnabled(true);
      final controller = AutomationController();
      await controller.load();
      await controller.saveRules([
        const AutomationRule(
          id: 'new',
          name: 'New',
          trigger: RuleTrigger.newNode,
          threshold: 0,
        ),
      ]);
      final pending = <Future<void>>[];
      final sub = controller.liveAlerts.listen(
        (a) => pending.add(notifications.showAlert(a)),
      );
      final now = DateTime.now();
      controller.seed([], radioId: 42);
      controller.observe(MeshNode(number: 7, lastHeard: now));
      await Future.wait(pending);
      await controller.historySaved;
      expect(backend.shown, hasLength(1));
      final restored = AutomationController();
      final restoredSub = restored.liveAlerts.listen(
        (a) => pending.add(notifications.showAlert(a)),
      );
      await restored.load();
      expect(restored.alerts, hasLength(1));
      expect(backend.shown, hasLength(1));
      await sub.cancel();
      await restoredSub.cancel();
      controller.dispose();
      restored.dispose();
      notifications.dispose();
    },
  );

  test(
    'OS errors do not discard a live alert or escape the event handler',
    () async {
      final backend = FakeAlerts();
      final notifications = AlertNotifications(backend: backend);
      await notifications.load();
      await notifications.setEnabled(true);
      backend.failShow = true;
      await notifications.showAlert(
        AutomationAlert('r', '!00000007', 'Battery low', DateTime.now()),
      );
      expect(notifications.error, contains('remains in AUTO'));
      backend.permission = false;
      await notifications.test();
      expect(notifications.enabled, false);
      notifications.dispose();
    },
  );
}
