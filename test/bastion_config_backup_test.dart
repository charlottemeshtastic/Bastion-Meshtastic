import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_config_backup.dart';

void main() {
  test('basic bastion_config_backup behavior', () {
    final encoded = BastionConfigBackup.exportSnapshot(config: [], channels: [], modules: []); expect(BastionConfigBackup.parse(encoded)['version'], 1); expect(() => BastionConfigBackup.parse('{}'), throwsFormatException);
  });
}
