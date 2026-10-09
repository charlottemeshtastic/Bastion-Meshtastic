import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_saved_radio.dart';

void main() {
  test('basic bastion_saved_radio behavior', () {
    final radios = BastionRadioSelection.recent([const BastionSavedRadio(deviceId: 'b', displayName: 'Beta'), const BastionSavedRadio(deviceId: 'a', displayName: 'Alpha')]); expect(radios.first.deviceId, 'a');
  });
}
