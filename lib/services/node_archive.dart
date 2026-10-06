import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mesh_node.dart';
import '../models/telemetry_sample.dart';

/// Phone-local, bounded archive, isolated by the connected radio identity.
class NodeArchive extends ChangeNotifier {
  NodeArchive({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  static const storageKey = 'bastion.nodes.v1';
  static const maxNodes = 2000;
  static const maxSamples = 4000;
  final DateTime Function() _clock;
  final Map<String, MeshNode> _nodes = {};
  final List<TelemetrySample> _samples = [];
  final Set<int> _radios = {};
  List<int> get radios => _radios.toList()..sort();
  bool loading = true;
  bool _loaded = false;
  bool _disposed = false;
  String? error;
  Future<void> _writes = Future<void>.value();
  Future<void> get saved => _writes;
  List<MeshNode> nodesFor(int radio) =>
      _nodes.entries
          .where((e) => e.key.startsWith('$radio:'))
          .map((e) => e.value)
          .toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
  List<TelemetrySample> samplesFor(int radio, int node) => List.unmodifiable(
    _samples.where((s) => s.radio == radio && s.node == node),
  );

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(storageKey);
      if (text != null) {
        final data = jsonDecode(text) as Map<String, dynamic>;
        // Decode into temporary collections so a corrupt file cannot half-load.
        final restoredNodes = <String, MeshNode>{};
        final restoredRadios = <int>{};
        for (final value in data['nodes'] as List) {
          final e = Map<String, dynamic>.from(value as Map);
          final radio = e['radio'] as int;
          final node = MeshNode.fromJson(
            Map<String, dynamic>.from(e['node'] as Map),
          );
          restoredNodes['$radio:${node.number}'] = node;
          restoredRadios.add(radio);
        }
        final restoredSamples = (data['samples'] as List)
            .map(
              (e) =>
                  TelemetrySample.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        _radios.addAll(restoredRadios);
        for (final e in restoredNodes.entries) {
          final live = _nodes[e.key];
          if (live == null ||
              (e.value.lastHeard != null &&
                  (live.lastHeard == null ||
                      e.value.lastHeard!.isAfter(live.lastHeard!)))) {
            _nodes[e.key] = e.value;
          }
        }
        _samples.insertAll(0, restoredSamples);
        _radios.addAll(restoredSamples.map((s) => s.radio));
      }
      _loaded = true;
      _trim();
      _changed();
    } catch (_) {
      error =
          'Saved nodes could not be loaded. Existing storage has been preserved.';
    } finally {
      loading = false;
      _notify();
    }
  }

  void seed(int radio, Iterable<MeshNode> nodes) {
    if (_disposed) {
      return;
    }
    _radios.add(radio);
    for (final node in nodes) {
      _upsert(radio, node);
    }
    _changed();
  }

  void observe(int radio, MeshNode node) {
    if (_disposed) {
      return;
    }
    _radios.add(radio);
    _upsert(radio, node);
    _changed();
  }

  void _upsert(int radio, MeshNode node) {
    final key = '$radio:${node.number}';
    final old = _nodes[key];
    if (old?.lastHeard != null &&
        (node.lastHeard == null || node.lastHeard!.isBefore(old!.lastHeard!))) {
      return;
    }
    final keepPosition =
        !node.hasPosition ||
        (old?.positionTime != null &&
            node.positionTime != null &&
            node.positionTime!.isBefore(old!.positionTime!));
    _nodes[key] = MeshNode(
      number: node.number,
      name: node.name ?? old?.name,
      lastHeard: node.lastHeard ?? old?.lastHeard,
      battery: node.powered ? null : node.battery ?? old?.battery,
      powered: node.battery != null || node.powered
          ? node.powered
          : old?.powered ?? false,
      snr: node.snr ?? old?.snr,
      rssi: node.rssi ?? old?.rssi,
      latitude: keepPosition ? old?.latitude : node.latitude,
      longitude: keepPosition ? old?.longitude : node.longitude,
      positionTime: keepPosition ? old?.positionTime : node.positionTime,
      hops: node.hops ?? old?.hops,
      viaMqtt: node.viaMqtt,
    );
  }

  void record(TelemetrySample sample) {
    if (_disposed || !sample.hasValues) {
      return;
    }
    _radios.add(sample.radio);
    _samples.add(sample);
    _changed();
  }

  Future<void> clearRadio(int radio) async {
    if (loading || !_loaded) {
      return;
    }
    _nodes.removeWhere((key, _) => key.startsWith('$radio:'));
    _samples.removeWhere((s) => s.radio == radio);
    _radios.remove(radio);
    _changed();
    await saved;
  }

  void _trim() {
    final cutoff = _clock().subtract(const Duration(days: 30));
    _samples.removeWhere((s) => s.time.isBefore(cutoff));
    _samples.sort((a, b) => a.time.compareTo(b.time));
    if (_samples.length > maxSamples) {
      _samples.removeRange(0, _samples.length - maxSamples);
    }
    if (_nodes.length > maxNodes) {
      final keys = _nodes.keys.toList()
        ..sort(
          (a, b) => (_nodes[a]!.lastHeard ?? DateTime(1970)).compareTo(
            _nodes[b]!.lastHeard ?? DateTime(1970),
          ),
        );
      for (final key in keys.take(_nodes.length - maxNodes)) {
        _nodes.remove(key);
      }
    }
  }

  void _changed() {
    _trim();
    if (_loaded) {
      final encoded = jsonEncode({
        'nodes': [
          for (final radio in radios)
            for (final node in nodesFor(radio))
              {'radio': radio, 'node': node.toJson()},
        ],
        'samples': _samples.map((s) => s.toJson()).toList(),
      });
      _writes = _writes.then((_) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (!await prefs.setString(storageKey, encoded)) {
            throw StateError('Save failed');
          }
        } catch (_) {
          error = 'Nodes are visible, but local storage could not be saved.';
          _notify();
        }
      });
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
