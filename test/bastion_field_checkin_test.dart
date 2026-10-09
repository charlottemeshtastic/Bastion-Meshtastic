import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_field_checkin.dart';

void main() {
  test('basic bastion_field_checkin behavior', () {
    expect(BastionFieldCheckin.compose(callsign: 'BCS', status: 'OK'), 'CHECK-IN | BCS | OK'); expect(() => BastionFieldCheckin.compose(callsign: '', status: 'OK'), throwsArgumentError);
  });
}
