import 'package:flutter_test/flutter_test.dart';
import 'package:bastion/services/bastion_owner_codec.dart';

void main() {
  test('encodes User long and short names in AdminMessage set_owner', () {
    final encoded = BastionOwnerCodec.encodeAdminSetOwner(
      longName: 'Bastion', shortName: 'BCS',
    );
    expect(encoded, [
      0x82, 0x02, 0x0e,
      0x12, 0x07, 66, 97, 115, 116, 105, 111, 110,
      0x1a, 0x03, 66, 67, 83,
    ]);
  });

  test('rejects invalid and oversized UTF-8 names', () {
    expect(() => BastionOwnerCodec.encodeUser(
      longName: '', shortName: 'BCS',
    ), throwsArgumentError);
    expect(() => BastionOwnerCodec.encodeUser(
      longName: 'Valid', shortName: 'ééé',
    ), throwsArgumentError);
  });
}
