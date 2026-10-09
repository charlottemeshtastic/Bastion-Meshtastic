/// Formats observed route hops without inventing missing nodes.
abstract final class BastionRouteSummary {
  static String describe(List<int> nodeNumbers) {
    if (nodeNumbers.isEmpty) return 'No route reported';
    return nodeNumbers.map((id) => '!${id.toRadixString(16).padLeft(8, '0')}').join(' → ');
  }

  static int? intermediateHops(List<int> nodeNumbers) =>
      nodeNumbers.isEmpty ? null : (nodeNumbers.length - 2).clamp(0, 1000000);
}
