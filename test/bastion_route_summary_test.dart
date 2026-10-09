import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_route_summary.dart';

void main() {
  test('basic bastion_route_summary behavior', () {
    expect(BastionRouteSummary.describe([]), 'No route reported'); expect(BastionRouteSummary.intermediateHops([1,2,3]), 1);
  });
}
