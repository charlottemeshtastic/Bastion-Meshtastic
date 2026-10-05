import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bastion_meshtastic/models/mesh_node.dart';
import 'package:bastion_meshtastic/services/automations/automation_controller.dart';
import 'package:bastion_meshtastic/services/automations/automation_engine.dart';
import 'package:bastion_meshtastic/models/telemetry_sample.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'downloaded node database seeds identity without new-node alerts',
    () async {
      final controller = AutomationController();
      await controller.load();
      await controller.saveRules([
        const AutomationRule(
          id: 'new',
          name: 'New',
          trigger: RuleTrigger.newNode,
          threshold: 0,
        ),
        const AutomationRule(
          id: 'battery',
          name: 'Battery',
          trigger: RuleTrigger.batteryBelow,
          threshold: 20,
        ),
      ]);
      final now = DateTime.now();
      controller.seed([MeshNode(number: 7, lastHeard: now, battery: 90)]);
      controller.observe(
        MeshNode(
          number: 7,
          lastHeard: now.add(const Duration(seconds: 1)),
          battery: 10,
        ),
      );
      expect(controller.alerts, hasLength(1));
      expect(controller.alerts.single.ruleId, 'battery');
      controller.observe(MeshNode(number: 8, lastHeard: now, powered: true));
      expect(controller.alerts.where((a) => a.ruleId == 'new'), hasLength(1));
      controller.dispose();
    },
  );

  test(
    'silent node requires uninterrupted monitoring; unknown timestamp stays unknown',
    () async {
      final controller = AutomationController();
      await controller.load();
      await controller.saveRules([
        const AutomationRule(
          id: 'silent',
          name: 'Silent',
          trigger: RuleTrigger.nodeSilent,
          threshold: 12,
        ),
      ]);
      final now = DateTime.now();
      controller.seed([
        MeshNode(number: 7, lastHeard: now.subtract(const Duration(days: 1))),
        const MeshNode(number: 8),
      ]);
      controller.tick(now, readySince: null);
      controller.tick(now, readySince: now.subtract(const Duration(hours: 1)));
      expect(controller.alerts, isEmpty);
      controller.tick(now, readySince: now.subtract(const Duration(hours: 13)));
      expect(controller.alerts, hasLength(1));
      expect(controller.alerts.single.nodeId, '!00000007');
      controller.dispose();
    },
  );

  test(
    'radio and node targeting persist and fresh measurements trigger the rule',
    () async {
      final controller = AutomationController();
      await controller.load();
      await controller.saveRules([
        const AutomationRule(
          id: 'target',
          name: 'Ridge battery',
          trigger: RuleTrigger.batteryBelow,
          threshold: 35,
          radioId: 42,
          nodeId: '!00000007',
        ),
      ]);
      final now = DateTime.now();
      controller.seed([
        MeshNode(number: 7, lastHeard: now, battery: 10),
      ], radioId: 42);
      controller.observe(
        MeshNode(number: 7, lastHeard: now, battery: 10),
        batteryFresh: false,
      );
      expect(controller.alerts, isEmpty);
      controller.observeTelemetry(
        TelemetrySample(radio: 42, node: 8, time: now, battery: 10),
      );
      controller.observeTelemetry(
        TelemetrySample(radio: 43, node: 7, time: now, battery: 10),
      );
      expect(controller.alerts, isEmpty);
      controller.observeTelemetry(
        TelemetrySample(radio: 42, node: 7, time: now, battery: 10),
      );
      expect(controller.alerts.single.radioId, 42);
      await controller.historySaved;
      final restored = AutomationController();
      await restored.load();
      expect(restored.rules.single.radioId, 42);
      expect(restored.rules.single.nodeId, '!00000007');
      expect(restored.rules.single.threshold, 35);
      expect(restored.alerts.single.radioId, 42);
      await restored.clearHistory();
      expect(restored.alerts, isEmpty);
      expect(restored.rules, hasLength(1));
      controller.dispose();
      restored.dispose();
    },
  );

  test('radio switch discards old nodes before silence monitoring', () async {
    final controller = AutomationController();
    await controller.load();
    await controller.saveRules([
      const AutomationRule(
        id: 'silent',
        name: 'Repeater',
        trigger: RuleTrigger.nodeSilent,
        threshold: 0.25,
      ),
    ]);
    final now = DateTime.now();
    controller.seed([
      MeshNode(number: 7, lastHeard: now.subtract(const Duration(days: 1))),
    ], radioId: 42);
    controller.seed([MeshNode(number: 8, lastHeard: now)], radioId: 43);
    controller.tick(now, readySince: now.subtract(const Duration(minutes: 20)));
    expect(controller.alerts, isEmpty);
    controller.dispose();
  });

  test('invalid thresholds leave the saved rules intact', () async {
    final controller = AutomationController();
    await controller.load();
    await controller.saveRules([
      const AutomationRule(
        id: 'valid',
        name: 'Watch',
        trigger: RuleTrigger.batteryBelow,
        threshold: 30,
      ),
    ]);
    await controller.saveRules([
      const AutomationRule(
        id: 'bad',
        name: 'Watch',
        trigger: RuleTrigger.batteryBelow,
        threshold: double.nan,
      ),
    ]);
    expect(controller.rules.single.id, 'valid');
    expect(controller.error, isNotNull);
    await controller.saveRules([
      const AutomationRule(
        id: 'bad',
        name: 'Watch',
        trigger: RuleTrigger.nodeSilent,
        threshold: 0.01,
      ),
    ]);
    expect(controller.rules.single.id, 'valid');
    controller.dispose();
  });
}
