/// Guards radio-setting edits before protobuf serialization.
abstract final class BastionLoraValidation {
  static String? hopLimitError(int value) {
    if (value < 0 || value > 7) return 'Hop limit must be between 0 and 7';
    return null;
  }

  static bool requiresMeshDisruptionWarning({
    required int previousRegion,
    required int nextRegion,
    required int previousPreset,
    required int nextPreset,
  }) => previousRegion != nextRegion || previousPreset != nextPreset;
}
