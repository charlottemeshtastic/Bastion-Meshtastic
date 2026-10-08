import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'meshtastic_phoneapi_codec.dart';
import 'meshtastic_radio_session.dart';

class MeshtasticNode {
  const MeshtasticNode({
    required this.num,
    this.id,
    this.longName,
    this.shortName,
    this.hardwareModel,
  });

  final int num;
  final String? id;
  final String? longName;
  final String? shortName;
  final int? hardwareModel;

  String get displayName => (longName?.isNotEmpty ?? false)
      ? longName!
      : (id ?? '!${num.toRadixString(16).padLeft(8, '0')}');
}

class MeshtasticNodeDatabase {
  MeshtasticNodeDatabase(this.session);

  final MeshtasticRadioSession session;
  final Map<int, MeshtasticNode> _nodes = {};
  final StreamController<List<MeshtasticNode>> _changes =
      StreamController<List<MeshtasticNode>>.broadcast();
  final StreamController<MeshtasticNode> _nodeUpdates =
      StreamController<MeshtasticNode>.broadcast();
  StreamSubscription<Uint8List>? _subscription;

  List<MeshtasticNode> get nodes {
    final values = _nodes.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return List.unmodifiable(values);
  }

  Stream<List<MeshtasticNode>> get changes => _changes.stream;
  Stream<MeshtasticNode> get nodeUpdates => _nodeUpdates.stream;

  Future<void> start() async {
    await _subscription?.cancel();
    _subscription = session.incomingEnvelopes.listen(_handleEnvelope);
  }

  void _handleEnvelope(Uint8List bytes) {
    final envelope = MeshtasticPhoneApiCodec.decodeFromRadio(bytes);
    if (envelope.kind != FromRadioPayloadKind.nodeInfo ||
        envelope.payload == null) {
      return;
    }
    final node = MeshtasticNodeInfoCodec.decode(envelope.payload!);
    _nodes[node.num] = node;
    _nodeUpdates.add(node);
    _changes.add(nodes);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _changes.close();
    await _nodeUpdates.close();
  }
}

abstract final class MeshtasticNodeInfoCodec {
  static MeshtasticNode decode(Uint8List bytes) {
    final fields = _fields(bytes);
    final num = fields.varint(1);
    if (num == null) {
      throw const FormatException('NodeInfo is missing node number.');
    }

    final userBytes = fields.bytes(2);
    String? id;
    String? longName;
    String? shortName;
    int? hardwareModel;
    if (userBytes != null) {
      final user = _fields(userBytes);
      id = user.string(1);
      longName = user.string(2);
      shortName = user.string(3);
      hardwareModel = user.varint(5);
    }

    return MeshtasticNode(
      num: num,
      id: id,
      longName: longName,
      shortName: shortName,
      hardwareModel: hardwareModel,
    );
  }

  static _ProtoFields _fields(Uint8List bytes) {
    final values = <int, Object>{};
    var offset = 0;
    while (offset < bytes.length) {
      final key = _readVarint(bytes, offset);
      offset = key.next;
      final field = key.value >> 3;
      final wire = key.value & 7;
      if (wire == 0) {
        final value = _readVarint(bytes, offset);
        values[field] = value.value;
        offset = value.next;
      } else if (wire == 2) {
        final length = _readVarint(bytes, offset);
        offset = length.next;
        final end = offset + length.value;
        if (end > bytes.length) {
          throw const FormatException('Truncated protobuf field.');
        }
        values[field] = Uint8List.sublistView(bytes, offset, end);
        offset = end;
      } else if (wire == 5) {
        if (offset + 4 > bytes.length) {
          throw const FormatException('Truncated fixed32 field.');
        }
        offset += 4;
      } else if (wire == 1) {
        if (offset + 8 > bytes.length) {
          throw const FormatException('Truncated fixed64 field.');
        }
        offset += 8;
      } else {
        throw FormatException('Unsupported protobuf wire type $wire.');
      }
    }
    return _ProtoFields(values);
  }

  static _Varint _readVarint(Uint8List bytes, int start) {
    var value = 0;
    var shift = 0;
    var offset = start;
    while (offset < bytes.length && shift < 64) {
      final byte = bytes[offset++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return _Varint(value, offset);
      shift += 7;
    }
    throw const FormatException('Invalid protobuf varint.');
  }
}

class _ProtoFields {
  const _ProtoFields(this.values);
  final Map<int, Object> values;

  int? varint(int field) => values[field] is int ? values[field] as int : null;
  Uint8List? bytes(int field) =>
      values[field] is Uint8List ? values[field] as Uint8List : null;
  String? string(int field) {
    final value = bytes(field);
    return value == null ? null : utf8.decode(value, allowMalformed: true);
  }
}

class _Varint {
  const _Varint(this.value, this.next);
  final int value;
  final int next;
}
