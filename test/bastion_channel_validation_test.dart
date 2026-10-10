import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_channel_validation.dart';

void main() {
  test('validates channel names', () {
    expect(BastionChannelValidation.nameError('BackCountry'), isNull);
    expect(BastionChannelValidation.nameError('BackCountryX'), isNotNull);
    expect(BastionChannelValidation.nameError('bad\nname'), isNotNull);
  });
  test('rejects invalid channel roles and slots', () {
    expect(BastionChannelValidation.slotError(index: 0, role: 0), isNotNull);
    expect(BastionChannelValidation.slotError(index: 2, role: 1), isNotNull);
    expect(BastionChannelValidation.slotError(index: 8, role: 2), isNotNull);
    expect(BastionChannelValidation.slotError(index: 1, role: 2), isNull);
  });
  test('checks UTF-8 bytes and key sizes', () {
    expect(BastionChannelValidation.nameError('éééééé'), isNotNull);
    expect(BastionChannelValidation.keyError(List.filled(5, 0)), isNotNull);
    expect(BastionChannelValidation.keyError(List.filled(16, 0)), isNull);
    expect(BastionChannelValidation.keyError([1]), isNull);
    expect(BastionChannelValidation.keyError([11]), isNotNull);
  });
  test('detects encryption key changes', () {
    expect(BastionChannelValidation.requiresKeyChangeConfirmation([1,2], [1,2]), isFalse);
    expect(BastionChannelValidation.requiresKeyChangeConfirmation([1,2], [1,3]), isTrue);
    expect(BastionChannelValidation.requiresKeyChangeConfirmation([1,2], [1]), isTrue);
  });
}
