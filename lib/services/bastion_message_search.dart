/// Local-only message search and draft length checks.
abstract final class BastionMessageSearch {
  static List<T> filter<T>(Iterable<T> messages, String query, String Function(T) textOf) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return List.unmodifiable(messages);
    return List.unmodifiable(messages.where((message) =>
        textOf(message).toLowerCase().contains(needle)));
  }

  static bool isValidDraft(String text) => text.trim().isNotEmpty;
}
