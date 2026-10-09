/// Channel editing safety checks. PSKs must never be logged.
abstract final class BastionChannelValidation {
  static String? nameError(String value) {
    if (value.runes.length > 11) return 'Channel name must be at most 11 characters';
    if (value.contains('\n') || value.contains('\r')) return 'Channel name must be one line';
    return null;
  }

  static bool requiresKeyChangeConfirmation(List<int> oldPsk, List<int> newPsk) {
    if (oldPsk.length != newPsk.length) return true;
    for (var i = 0; i < oldPsk.length; i++) {
      if (oldPsk[i] != newPsk[i]) return true;
    }
    return false;
  }
}
