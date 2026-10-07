import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'meshtastic_node_database.dart';

class BastionNodeRecord {
  const BastionNodeRecord({
    required this.num,
    required this.firstSeen,
    required this.lastSeen,
    required this.encounters,
    this.id,
    this.longName,
    this.shortName,
    this.hardwareModel,
    this.favorite = false,
    this.note = '',
  });

  final int num;
  final String? id;
  final String? longName;
  final String? shortName;
  final int? hardwareModel;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int encounters;
  final bool favorite;
  final String note;

  String get displayName => (longName?.isNotEmpty ?? false)
      ? longName!
      : (id ?? '!${num.toRadixString(16).padLeft(8, '0')}');

  BastionNodeRecord copyWith({
    String? id, String? longName, String? shortName, int? hardwareModel,
    DateTime? lastSeen, int? encounters, bool? favorite, String? note,
  }) => BastionNodeRecord(
    num: num, id: id ?? this.id, longName: longName ?? this.longName,
    shortName: shortName ?? this.shortName,
    hardwareModel: hardwareModel ?? this.hardwareModel,
    firstSeen: firstSeen, lastSeen: lastSeen ?? this.lastSeen,
    encounters: encounters ?? this.encounters,
    favorite: favorite ?? this.favorite, note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'num': num, 'id': id, 'longName': longName, 'shortName': shortName,
    'hardwareModel': hardwareModel,
    'firstSeen': firstSeen.toUtc().toIso8601String(),
    'lastSeen': lastSeen.toUtc().toIso8601String(),
    'encounters': encounters, 'favorite': favorite, 'note': note,
  };

  static BastionNodeRecord fromJson(Map<String, Object?> json) =>
      BastionNodeRecord(
        num: json['num']! as int, id: json['id'] as String?,
        longName: json['longName'] as String?,
        shortName: json['shortName'] as String?,
        hardwareModel: json['hardwareModel'] as int?,
        firstSeen: DateTime.parse(json['firstSeen']! as String).toLocal(),
        lastSeen: DateTime.parse(json['lastSeen']! as String).toLocal(),
        encounters: json['encounters']! as int,
        favorite: json['favorite'] as bool? ?? false,
        note: json['note'] as String? ?? '',
      );
}

class BastionNodeDex {
  BastionNodeDex({SharedPreferencesAsync? preferences})
      : _preferences = preferences;

  static const _key = 'bastion.nodedex.v1';
  SharedPreferencesAsync? _preferences;
  SharedPreferencesAsync get _store =>
      _preferences ??= SharedPreferencesAsync();
  final Map<int, BastionNodeRecord> _records = {};

  List<BastionNodeRecord> get records {
    final result = _records.values.toList()
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return b.lastSeen.compareTo(a.lastSeen);
      });
    return List.unmodifiable(result);
  }

  Future<void> load() async {
    try {
      final raw = await _store.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map) {
          final record = BastionNodeRecord.fromJson(
            Map<String, Object?>.from(item),
          );
          _records[record.num] = record;
        }
      }
    } catch (_) {}
  }

  Future<void> observe(MeshtasticNode node) async {
    final now = DateTime.now();
    final old = _records[node.num];
    _records[node.num] = old == null
        ? BastionNodeRecord(
            num: node.num, id: node.id, longName: node.longName,
            shortName: node.shortName, hardwareModel: node.hardwareModel,
            firstSeen: now, lastSeen: now, encounters: 1)
        : old.copyWith(
            id: node.id, longName: node.longName, shortName: node.shortName,
            hardwareModel: node.hardwareModel, lastSeen: now,
            encounters: old.encounters + 1);
    await _save();
  }

  Future<void> setFavorite(int num, bool value) async {
    final old = _records[num];
    if (old == null) return;
    _records[num] = old.copyWith(favorite: value);
    await _save();
  }

  Future<void> setNote(int num, String value) async {
    final old = _records[num];
    if (old == null) return;
    _records[num] = old.copyWith(note: value.trim());
    await _save();
  }

  Future<void> _save() async {
    try {
      await _store.setString(
        _key,
        jsonEncode(_records.values.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}
  }
}
