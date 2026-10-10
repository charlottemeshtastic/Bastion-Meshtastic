/// Local keyword matching for optional auto-replies.
class BastionBotRule {
  const BastionBotRule({required this.keyword, required this.reply, this.enabled = true});
  final String keyword;
  final String reply;
  final bool enabled;
}

abstract final class BastionBotRules {
  static String? match(String message, Iterable<BastionBotRule> rules) {
    final input = message.toLowerCase();
    for (final rule in rules) {
      final key = rule.keyword.trim().toLowerCase();
      if (rule.enabled && key.isNotEmpty && rule.reply.trim().isNotEmpty && input.contains(key)) {
        return rule.reply;
      }
    }
    return null;
  }
}
