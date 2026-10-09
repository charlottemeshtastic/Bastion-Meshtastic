/// Validates user-entered Meshtastic node names before a radio write.
abstract final class BastionNodeIdentityValidation {
  static String? longNameError(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Long name cannot be empty';
    if (name.runes.length > 39) return 'Long name must be at most 39 characters';
    if (name.contains('\n') || name.contains('\r')) return 'Long name must be one line';
    return null;
  }

  static String? shortNameError(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Short name cannot be empty';
    if (name.runes.length > 4) return 'Short name must be at most 4 characters';
    if (name.contains('\n') || name.contains('\r')) return 'Short name must be one line';
    return null;
  }
}
