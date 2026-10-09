import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_bot_rules.dart';

void main() {
  test('basic bastion_bot_rules behavior', () {
    expect(BastionBotRules.match('PING', [const BastionBotRule(keyword: 'ping', reply: 'pong')]), 'pong'); expect(BastionBotRules.match('ping', [const BastionBotRule(keyword: 'ping', reply: 'pong', enabled: false)]), isNull);
  });
}
