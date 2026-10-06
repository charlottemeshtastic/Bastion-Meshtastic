import 'package:flutter_test/flutter_test.dart';
import 'package:bastion_meshtastic/services/automations/automation_engine.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5);
  const battery = AutomationRule(
    id: 'battery',
    name: 'Battery',
    trigger: RuleTrigger.batteryBelow,
    threshold: 20,
  );
  NodeObservation node(int seconds, double? level) => NodeObservation(
    id: '!1234',
    lastHeard: now.add(Duration(seconds: seconds)),
    battery: level,
  );

  test(
    'battery alerts once, ignores unknown values, and rearms on recovery',
    () {
      final engine = AutomationEngine();
      expect(engine.observe(node(0, null), [battery], now), isEmpty);
      expect(engine.observe(node(1, 15), [battery], now), hasLength(1));
      expect(engine.observe(node(2, 10), [battery], now), isEmpty);
      expect(engine.observe(node(3, 20), [battery], now), isEmpty);
      expect(engine.observe(node(4, 19), [battery], now), hasLength(1));
    },
  );

  test('old packets cannot reset battery alert state', () {
    final engine = AutomationEngine();
    engine.observe(node(2, 10), [battery], now);
    engine.observe(node(1, 80), [battery], now);
    expect(engine.observe(node(3, 10), [battery], now), isEmpty);
  });

  test(
    'silence requires connected monitoring and rearms after fresh contact',
    () {
      const silent = AutomationRule(
        id: 'silent',
        name: 'Silent',
        trigger: RuleTrigger.nodeSilent,
        threshold: 12,
      );
      final engine = AutomationEngine();
      engine.observe(node(0, null), [silent], now);
      final later = now.add(const Duration(hours: 13));
      expect(engine.tick([silent], later, monitoringConnected: false), isEmpty);
      expect(
        engine.tick([silent], later, monitoringConnected: true),
        hasLength(1),
      );
      expect(engine.tick([silent], later, monitoringConnected: true), isEmpty);
      engine.observe(NodeObservation(id: '!1234', lastHeard: later), [
        silent,
      ], later);
      expect(
        engine.tick(
          [silent],
          later.add(const Duration(hours: 13)),
          monitoringConnected: true,
        ),
        hasLength(1),
      );
    },
  );

  test('new-node alerts deduplicate and respect target and enabled state', () {
    const rule = AutomationRule(
      id: 'new',
      name: 'New',
      trigger: RuleTrigger.newNode,
      threshold: 0,
      nodeId: '!1234',
    );
    final engine = AutomationEngine();
    expect(engine.observe(node(0, null), [rule], now), hasLength(1));
    expect(engine.observe(node(1, null), [rule], now), isEmpty);
    expect(
      AutomationEngine().observe(node(0, null), [rule.withEnabled(false)], now),
      isEmpty,
    );
    expect(
      AutomationEngine().observe(
        NodeObservation(id: '!other', lastHeard: now),
        [rule],
        now,
      ),
      isEmpty,
    );
  });

  test('rules survive JSON round trip', () {
    final restored = AutomationRule.fromJson(
      battery.withEnabled(false).toJson(),
    );
    expect(restored.id, battery.id);
    expect(restored.trigger, RuleTrigger.batteryBelow);
    expect(restored.enabled, isFalse);
  });

  test(
    'fresh battery can arrive after a node event in the same timestamp second',
    () {
      final engine = AutomationEngine();
      engine.observe(node(0, null), [battery], now);
      expect(engine.observeBattery(node(0, 10), [battery], now), hasLength(1));
      expect(engine.observeBattery(node(0, 10), [battery], now), isEmpty);
      expect(engine.observeBattery(node(0, 90), [battery], now), isEmpty);
      expect(engine.observeBattery(node(0, 10), [battery], now), hasLength(1));
    },
  );

  test(
    'edited rule can rearm independently while unrelated rules stay active',
    () {
      final engine = AutomationEngine();
      const second = AutomationRule(
        id: 'second',
        name: 'Second',
        trigger: RuleTrigger.batteryBelow,
        threshold: 20,
      );
      expect(engine.observe(node(0, 10), [battery, second], now), hasLength(2));
      engine.forgetRule('battery');
      final events = engine.observe(node(1, 10), [battery, second], now);
      expect(events.single.ruleId, 'battery');
    },
  );
}
