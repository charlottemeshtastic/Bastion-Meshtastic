/// Radio selection metadata. Do not treat BLE discovery as an authenticated mesh identity.
class BastionSavedRadio {
  const BastionSavedRadio({required this.deviceId, required this.displayName, this.lastConnected});
  final String deviceId;
  final String displayName;
  final DateTime? lastConnected;
}

abstract final class BastionRadioSelection {
  static List<BastionSavedRadio> recent(Iterable<BastionSavedRadio> radios) {
    final result = radios.toList();
    result.sort((a, b) {
      final aTime = a.lastConnected;
      final bTime = b.lastConnected;
      if (aTime == null && bTime == null) return a.displayName.compareTo(b.displayName);
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return List.unmodifiable(result);
  }
}
