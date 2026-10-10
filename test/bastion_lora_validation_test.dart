import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_lora_validation.dart';

void main() {
  test('rejects invalid hop limits', () {
    expect(BastionLoraValidation.hopLimitError(-1), isNotNull);
    expect(BastionLoraValidation.hopLimitError(0), isNull);
    expect(BastionLoraValidation.hopLimitError(7), isNull);
    expect(BastionLoraValidation.hopLimitError(8), isNotNull);
  });
  test('warns about region or preset changes', () {
    expect(BastionLoraValidation.requiresMeshDisruptionWarning(previousRegion: 1, nextRegion: 2, previousPreset: 0, nextPreset: 0), isTrue);
    expect(BastionLoraValidation.requiresMeshDisruptionWarning(previousRegion: 1, nextRegion: 1, previousPreset: 0, nextPreset: 0), isFalse);
  });
}
