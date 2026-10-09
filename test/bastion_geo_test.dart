import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_geo.dart';

void main() {
  test('basic bastion_geo behavior', () {
    expect(BastionGeo.distanceMeters(0, 0, 0, 0), closeTo(0, 0.01)); expect(() => BastionGeo.distanceMeters(91, 0, 0, 0), throwsArgumentError);
  });
}
