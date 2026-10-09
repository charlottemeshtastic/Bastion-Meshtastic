import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_message_search.dart';

void main() {
  test('basic bastion_message_search behavior', () {
    expect(BastionMessageSearch.filter(['Alpha','Bravo'], 'ALP', (s) => s), ['Alpha']); expect(BastionMessageSearch.isValidDraft('  '), isFalse);
  });
}
