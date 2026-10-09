import 'dart:convert';

/// Channel editing safety checks. PSKs must never be logged.
abstract final class BastionChannelValidation {
  static String? nameError(String value) {
    if (utf8.encode(value).length > 11) return 'Channel name must be at most 11 UTF-8 bytes';
    if (value.contains('\n') || value.contains('\r')) return 'Channel name must be one line';
    return null;
  }

  static String? keyError(List<int> key) {
    if (key.isEmpty || key.length == 16 || key.length == 32) return null;
    if (key.length == 1 && key.first >= 0 && key.first <= 10) return null;
    return 'Channel key must be empty, a supported shorthand, 16, or 32 bytes';
  }

  static String? slotError({required int index, required int role}) {
    if (index < 0 || index > 7) return 'Channel slot must be 0 through 7';
    if (role < 0 || role > 2) return 'Unknown channel role';
    if (index == 0 && role != 1) return 'Primary channel must remain enabled';
    if (index != 0 && role == 1) return 'Only slot 0 can be primary';
    return null;
  }

  static String? validate({
    required int index,
    required int role,
    required String name,
    required List<int> key,
  }) => slotError(index: index, role: role) ??
      nameError(name) ??
      keyError(key);

  static bool requiresKeyChangeConfirmation(List<int> oldPsk, List<int> newPsk) {
    if (oldPsk.length != newPsk.length) return true;
    for (var i = 0; i < oldPsk.length; i++) {
      if (oldPsk[i] != newPsk[i]) return true;
    }
    return false;
  }
}
