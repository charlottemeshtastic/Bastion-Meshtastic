import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:protobuf/protobuf.dart';

/// Renders an editable form for any generated protobuf message.
///
/// Used for Meshtastic settings that have no hand-built editor, so every
/// config and module field the firmware defines is reachable. Bytes and
/// repeated fields are shown read-only. Nested messages are created only
/// when one of their fields is edited, so viewing never marks a draft dirty.
class ProtoFieldList extends StatelessWidget {
  const ProtoFieldList({
    super.key,
    required this.message,
    required this.writable,
    required this.changed,
  });

  /// The values to display. May be a read-only default for an unset field.
  final GeneratedMessage message;

  /// Returns the writable message to edit, creating it if needed.
  final GeneratedMessage Function() writable;

  final VoidCallback changed;

  static int _base(int type) => PbFieldType.baseType(type);

  static bool _isInt32(int base) => const {
    PbFieldType.INT32_BIT,
    PbFieldType.SINT32_BIT,
    PbFieldType.UINT32_BIT,
    PbFieldType.FIXED32_BIT,
    PbFieldType.SFIXED32_BIT,
  }.contains(base);

  static bool _isInt64(int base) => const {
    PbFieldType.INT64_BIT,
    PbFieldType.SINT64_BIT,
    PbFieldType.UINT64_BIT,
    PbFieldType.FIXED64_BIT,
    PbFieldType.SFIXED64_BIT,
  }.contains(base);

  static bool _isUnsigned(int base) => const {
    PbFieldType.UINT32_BIT,
    PbFieldType.FIXED32_BIT,
    PbFieldType.UINT64_BIT,
    PbFieldType.FIXED64_BIT,
  }.contains(base);

  /// "positionBroadcastSecs" → "Position broadcast secs".
  static String label(String name) {
    final words = name
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]}')
        .toLowerCase();
    return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
  }

  static String enumLabel(ProtobufEnum value) => value.name
      .split('_')
      .map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase())
      .join(' ');

  void _set(int tag, Object value) {
    writable().setField(tag, value);
    changed();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final field in message.info_.sortedByTag) _field(context, field),
    ],
  );

  Widget _field(BuildContext context, FieldInfo<dynamic> field) {
    final tag = field.tagNumber;
    final name = label(field.name);
    final base = _base(field.type);
    final value = message.getField(tag);

    if (field.isRepeated || field.isMapField) {
      final count = (value as List).length;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(name),
        subtitle: Text(
          '$count item${count == 1 ? '' : 's'} • not editable here',
        ),
      );
    }
    if (field.isGroupOrMessage) {
      GeneratedMessage nested() {
        final parent = writable();
        if (!parent.hasField(tag)) parent.setField(tag, field.subBuilder!());
        return parent.getField(tag) as GeneratedMessage;
      }

      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(name),
        childrenPadding: const EdgeInsetsDirectional.only(start: 16, bottom: 8),
        children: [
          ProtoFieldList(
            message: value as GeneratedMessage,
            writable: nested,
            changed: changed,
          ),
        ],
      );
    }
    if (field.isEnum) {
      final values = field.enumValues!;
      final current = value as ProtobufEnum;
      return DropdownButtonFormField<ProtobufEnum>(
        initialValue: values.contains(current) ? current : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: name),
        items: [
          for (final v in values)
            DropdownMenuItem(value: v, child: Text(enumLabel(v))),
        ],
        onChanged: (v) {
          if (v != null) _set(tag, v);
        },
      );
    }
    if (base == PbFieldType.BOOL_BIT) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(name),
        value: value as bool,
        onChanged: (v) => _set(tag, v),
      );
    }
    if (base == PbFieldType.BYTES_BIT) {
      final length = (value as List<int>).length;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(name),
        subtitle: Text(
          length == 0 ? 'Not set' : '$length bytes • not editable here',
        ),
      );
    }
    if (base == PbFieldType.STRING_BIT) {
      return _TextValue(
        key: ValueKey(tag),
        label: name,
        initial: value as String,
        onChanged: (v) => _set(tag, v),
      );
    }
    if (base == PbFieldType.DOUBLE_BIT || base == PbFieldType.FLOAT_BIT) {
      return _TextValue(
        key: ValueKey(tag),
        label: name,
        initial: '$value',
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        validator: (v) => double.tryParse(v) == null ? 'Enter a number' : null,
        onChanged: (v) {
          final parsed = double.tryParse(v);
          if (parsed != null) _set(tag, parsed);
        },
      );
    }
    if (_isInt32(base) || _isInt64(base)) {
      final unsigned = _isUnsigned(base);
      int? parse(String v) {
        final parsed = int.tryParse(v.trim());
        if (parsed == null || (unsigned && parsed < 0)) return null;
        if (_isInt32(base) &&
            (unsigned ? parsed > 0xffffffff : parsed.abs() > 0x7fffffff)) {
          return null;
        }
        return parsed;
      }

      return _TextValue(
        key: ValueKey(tag),
        label: name,
        initial: '$value',
        keyboardType: TextInputType.numberWithOptions(signed: !unsigned),
        validator: (v) => parse(v) == null
            ? (unsigned
                  ? 'Enter a whole number, 0 or more'
                  : 'Enter a whole number')
            : null,
        onChanged: (v) {
          final parsed = parse(v);
          if (parsed != null)
            _set(tag, _isInt64(base) ? Int64(parsed) : parsed);
        },
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      subtitle: Text('$value'),
    );
  }
}

class _TextValue extends StatefulWidget {
  const _TextValue({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final String? Function(String)? validator;

  @override
  State<_TextValue> createState() => _TextValueState();
}

class _TextValueState extends State<_TextValue> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    keyboardType: widget.keyboardType,
    decoration: InputDecoration(labelText: widget.label, errorText: _error),
    onChanged: (v) {
      setState(() => _error = widget.validator?.call(v));
      widget.onChanged(v);
    },
  );
}
