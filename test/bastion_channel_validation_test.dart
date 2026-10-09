import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_channel_validation.dart';

void main() {
  test('validates channel names', () {
    expect(BastionChannelValidation.nameError('BackCountry'), isNull);
    expect(BastionChannelValidation.nameError('BackCountryX'), isNotNull);
    expect(BastionChannelValidation.nameError('bad\nname'), isNotNull);
  });
  test('detects encryption key changes', () {
    expect(BastionChannelValidation.requiresKeyChangeConfirmation([1,2], [1,2]), isFalse);
    expect(BastionChannelValidation.requiresKeyChangeConfirmation([1,2], [1,3]), isTrue);
    expect(BastionChannelValidation.requiresKeyChangeConfirmation([1,2], [1]), isTrue);
  });
}
