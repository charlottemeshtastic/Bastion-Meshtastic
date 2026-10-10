/// Check-in composition. Sending is not proof of mesh delivery.
abstract final class BastionFieldCheckin {
  static String compose({required String callsign, required String status, String? location}) {
    final name = callsign.trim();
    final state = status.trim();
    if (name.isEmpty || state.isEmpty) throw ArgumentError('Callsign and status are required');
    final place = location?.trim();
    return 'CHECK-IN | $name | $state${place == null || place.isEmpty ? '' : ' | $place'}';
  }

  static const deliveryNotice =
      'Queued or transmitted does not mean received. Confirm with an acknowledgment or voice contact.';
}
