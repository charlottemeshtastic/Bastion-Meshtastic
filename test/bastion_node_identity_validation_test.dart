import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_node_identity_validation.dart';

void main() {
  test('node identity validates required and maximum lengths', () {
    expect(BastionNodeIdentityValidation.longNameError(''), isNotNull);
    expect(BastionNodeIdentityValidation.longNameError('Field Radio'), isNull);
    expect(BastionNodeIdentityValidation.longNameError('a' * 40), isNotNull);
    expect(BastionNodeIdentityValidation.shortNameError('BCS'), isNull);
    expect(BastionNodeIdentityValidation.shortNameError('ABCDE'), isNotNull);
    expect(BastionNodeIdentityValidation.shortNameError('A\nB'), isNotNull);
  });
}
