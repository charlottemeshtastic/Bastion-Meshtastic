import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/models/mesh_node.dart';
import 'package:bastion_meshtastic/services/automations/automation_controller.dart';
import 'package:bastion_meshtastic/services/automations/automation_engine.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('downloaded node database seeds identity without new-node alerts', () async {
    final controller = AutomationController();
    await controller.load();
    await controller.saveRules([
      const AutomationRule(id: 'new', name: 'New', trigger: RuleTrigger.newNode, threshold: 0),
      const AutomationRule(id: 'battery', name: 'Battery', trigger: RuleTrigger.batteryBelow, threshold: 20),
    ]);
    final now = DateTime.now();
    controller.seed([MeshNode(number: 7, lastHeard: now, battery: 90)]);
    controller.observe(MeshNode(number: 7, lastHeard: now.add(const Duration(seconds: 1)), battery: 10));
    expect(controller.alerts, hasLength(1));
    expect(controller.alerts.single.ruleId, 'battery');
    controller.observe(MeshNode(number: 8, lastHeard: now, powered: true));
    expect(controller.alerts.where((a) => a.ruleId == 'new'), hasLength(1));
    controller.dispose();
  });

  test('silent node requires uninterrupted monitoring; unknown timestamp stays unknown', () async {
    final controller = AutomationController();
    await controller.load();
    await controller.saveRules([
      const AutomationRule(id: 'silent', name: 'Silent', trigger: RuleTrigger.nodeSilent, threshold: 12),
    ]);
    final now = DateTime.now();
    controller.seed([MeshNode(number: 7, lastHeard: now.subtract(const Duration(days: 1))),
      const MeshNode(number: 8)]);
    controller.tick(now, readySince: null);
    controller.tick(now, readySince: now.subtract(const Duration(hours: 1)));
    expect(controller.alerts, isEmpty);
    controller.tick(now, readySince: now.subtract(const Duration(hours: 13)));
    expect(controller.alerts, hasLength(1));
    expect(controller.alerts.single.nodeId, '!00000007');
    controller.dispose();
  });
}
