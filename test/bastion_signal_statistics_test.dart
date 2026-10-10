import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_signal_statistics.dart';

void main() {
  test('basic bastion_signal_statistics behavior', () {
    expect(BastionSignalStatistics.mean([1,2,3]), 2); expect(BastionSignalStatistics.mean([]), isNull);
  });
}
