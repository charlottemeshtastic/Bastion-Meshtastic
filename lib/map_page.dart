import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'node_detail_page.dart';
import 'services/bastion_geo.dart';
import 'services/bastion_waypoints.dart';
import 'services/meshtastic_node_database.dart';
import 'services/meshtastic_radio_coordinator.dart';

/// Mesh nodes with a reported position on an OpenStreetMap base map.
///
/// Tiles load from tile.openstreetmap.org and need internet access; node
/// positions come only from the radio.
class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.radio});

  final MeshtasticRadioCoordinator radio;

  static const accent = Color(0xFFC7A24A);

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _map = MapController();
  bool _fitted = false;
  bool _showLinks = true;

  /// One line per pair of placed nodes that a Neighbor Info report links.
  List<Polyline> _links(List<MeshtasticNode> placed) {
    final byNum = {for (final n in placed) n.num: n};
    final seen = <(int, int)>{};
    final lines = <Polyline>[];
    for (final report in widget.radio.neighborReports.values) {
      final a = byNum[report.nodeNum];
      if (a == null) continue;
      for (final neighbor in report.neighbors) {
        final b = byNum[neighbor.nodeNum];
        if (b == null) continue;
        final key = a.num < b.num ? (a.num, b.num) : (b.num, a.num);
        if (!seen.add(key)) continue;
        lines.add(Polyline(
          points: [LatLng(a.latitude!, a.longitude!), LatLng(b.latitude!, b.longitude!)],
          strokeWidth: 2.5,
          color: MapPage.accent.withValues(alpha: neighbor.snr >= 0 ? 0.9 : 0.45),
        ));
      }
    }
    return lines;
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  List<MeshtasticNode> get _placed =>
      widget.radio.nodes.where((n) => n.hasPosition).toList();

  void _fit(List<MeshtasticNode> nodes) {
    if (nodes.isEmpty) return;
    final points = [for (final n in nodes) LatLng(n.latitude!, n.longitude!)];
    if (points.length == 1) {
      _map.move(points.single, 13);
    } else {
      _map.fitCamera(CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(48),
        maxZoom: 15,
      ));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.radio,
        builder: (context, _) {
          final placed = _placed;
          final local = widget.radio.localNodeNum;
          if (!_fitted && placed.isNotEmpty) {
            _fitted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fit(placed);
            });
          }
          return Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: const LatLng(39.5, -98.35),
                  initialZoom: 3,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onLongPress: (_, point) => _createWaypoint(context, point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'org.backcountrysignal.bastion',
                    maxNativeZoom: 19,
                  ),
                  if (_showLinks) PolylineLayer(polylines: _links(placed)),
                  MarkerLayer(
                    markers: [
                      for (final waypoint in widget.radio.waypoints)
                        Marker(
                          point: LatLng(waypoint.latitude, waypoint.longitude),
                          width: 120,
                          height: 56,
                          child: _WaypointPin(
                            waypoint: waypoint,
                            onTap: () => _showWaypoint(context, waypoint),
                          ),
                        ),
                      for (final node in placed)
                        Marker(
                          point: LatLng(node.latitude!, node.longitude!),
                          width: 64,
                          height: 64,
                          child: _NodePin(
                            node: node,
                            isLocal: node.num == local,
                            onTap: () => _showNode(context, node),
                          ),
                        ),
                    ],
                  ),
                  const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                ],
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.map_outlined, color: MapPage.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            placed.isEmpty
                                ? (widget.radio.isReady
                                    ? 'No node has reported a position yet'
                                    : 'Connect a radio to show node positions')
                                : '${placed.length} of ${widget.radio.nodes.length} nodes placed'
                                    '${widget.radio.waypoints.isEmpty ? '' : ' • ${widget.radio.waypoints.length} waypoints'}'
                                    '\nLong-press the map to drop a waypoint',
                          ),
                        ),
                        if (widget.radio.neighborReports.isNotEmpty)
                          IconButton(
                            tooltip: _showLinks ? 'Hide radio links' : 'Show radio links',
                            icon: Icon(_showLinks ? Icons.hub : Icons.hub_outlined),
                            onPressed: () => setState(() => _showLinks = !_showLinks),
                          ),
                        if (placed.isNotEmpty)
                          IconButton(
                            tooltip: 'Show all nodes',
                            icon: const Icon(Icons.fit_screen),
                            onPressed: () => _fit(placed),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

  Future<void> _createWaypoint(BuildContext context, LatLng point) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!widget.radio.isReady) {
      messenger.showSnackBar(const SnackBar(content: Text('Connect a radio to share waypoints.')));
      return;
    }
    final waypoint = await showDialog<MeshWaypoint>(
      context: context,
      builder: (_) => _WaypointDialog(point: point, localNodeNum: widget.radio.localNodeNum),
    );
    if (waypoint == null) return;
    try {
      await widget.radio.sendWaypoint(waypoint);
      messenger.showSnackBar(SnackBar(content: Text('Waypoint "${waypoint.name}" shared on channel 0.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not share waypoint: $error')));
    }
  }

  void _showWaypoint(BuildContext context, MeshWaypoint waypoint) {
    String? sender;
    if (waypoint.from != null) {
      sender = '!${waypoint.from!.toRadixString(16).padLeft(8, '0')}';
      for (final node in widget.radio.nodes) {
        if (node.num == waypoint.from) sender = node.displayName;
      }
    }
    final canDelete = widget.radio.isReady && widget.radio.canEditWaypoint(waypoint);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${waypoint.iconText} ${waypoint.name}',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              if (waypoint.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(waypoint.description),
              ],
              const SizedBox(height: 12),
              Text('${waypoint.latitude.toStringAsFixed(5)}, ${waypoint.longitude.toStringAsFixed(5)}'),
              Text(waypoint.expires == null
                  ? 'Never expires'
                  : 'Expires ${waypoint.expires!.toLocal().toString().substring(0, 16)}'),
              if (sender != null) Text('Shared by $sender'),
              if (waypoint.lockedTo != 0) const Text('Locked to its creator'),
              const SizedBox(height: 12),
              if (canDelete)
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete for everyone'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.of(sheetContext).pop();
                    try {
                      await widget.radio.deleteWaypoint(waypoint);
                      messenger.showSnackBar(SnackBar(content: Text('Deleted "${waypoint.name}".')));
                    } catch (error) {
                      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $error')));
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNode(BuildContext context, MeshtasticNode node) {
    final localNode = widget.radio.localNode;
    final distance = localNode != null && localNode.hasPosition && localNode.num != node.num
        ? BastionGeo.distanceMeters(
            localNode.latitude!, localNode.longitude!, node.latitude!, node.longitude!)
        : null;
    String ago(DateTime? time) {
      if (time == null) return 'unknown';
      final d = DateTime.now().difference(time);
      if (d.inMinutes < 1) return 'just now';
      if (d.inHours < 1) return '${d.inMinutes} min ago';
      if (d.inDays < 1) return '${d.inHours} h ago';
      return '${d.inDays} d ago';
    }

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(node.displayName, style: Theme.of(context).textTheme.titleLarge),
              if (node.shortName != null) Text(node.shortName!),
              const SizedBox(height: 12),
              Text('${node.latitude!.toStringAsFixed(5)}, ${node.longitude!.toStringAsFixed(5)}'
                  '${node.altitudeMeters == null ? '' : ' • ${node.altitudeMeters} m'}'),
              if (distance != null)
                Text(distance < 1000
                    ? '${distance.round()} m from this radio'
                    : '${(distance / 1000).toStringAsFixed(1)} km from this radio'),
              Text('Position: ${ago(node.positionTime)} • Heard: ${ago(node.lastHeard)}'),
              if (node.snr != null || node.hopsAway != null)
                Text([
                  if (node.snr != null) 'SNR ${node.snr!.toStringAsFixed(1)} dB',
                  if (node.hopsAway != null)
                    node.hopsAway == 0 ? 'direct' : '${node.hopsAway} hops',
                ].join(' • ')),
              if (node.batteryLevel != null)
                Text(node.batteryLevel! > 100
                    ? 'Battery: external power'
                    : 'Battery: ${node.batteryLevel}%'),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.info_outline),
                label: const Text('Open details'),
                onPressed: () {
                  Navigator.of(context)
                    ..pop()
                    ..push(MaterialPageRoute<void>(
                      builder: (_) => NodeDetailPage(radio: widget.radio, nodeNum: node.num),
                    ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodePin extends StatelessWidget {
  const _NodePin({required this.node, required this.isLocal, required this.onTap});

  final MeshtasticNode node;
  final bool isLocal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = node.shortName ?? node.displayName.characters.take(4).toString();
    return Semantics(
      button: true,
      label: '${node.displayName}${isLocal ? ', this radio' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isLocal ? MapPage.accent : const Color(0xFF151713),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MapPage.accent, width: 2),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isLocal ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            Icon(isLocal ? Icons.my_location : Icons.location_on,
                color: MapPage.accent, size: 26),
          ],
        ),
      ),
    );
  }
}

class _WaypointPin extends StatelessWidget {
  const _WaypointPin({required this.waypoint, required this.onTap});

  final MeshWaypoint waypoint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Waypoint ${waypoint.name}',
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(waypoint.iconText, style: const TextStyle(fontSize: 26)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.black54,
                child: Text(
                  waypoint.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
}

class _WaypointDialog extends StatefulWidget {
  const _WaypointDialog({required this.point, required this.localNodeNum});

  final LatLng point;
  final int? localNodeNum;

  @override
  State<_WaypointDialog> createState() => _WaypointDialogState();
}

class _WaypointDialogState extends State<_WaypointDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _icon = '📍';
  Duration? _lifetime = const Duration(days: 1);
  bool _locked = false;

  static const _icons = ['📍', '⛺', '🚩', '⚠️', '💧', '🚗', '🏠', '📡'];
  static const _lifetimes = <(String, Duration?)>[
    ('1 hour', Duration(hours: 1)),
    ('1 day', Duration(days: 1)),
    ('1 week', Duration(days: 7)),
    ('Never', null),
  ];

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return AlertDialog(
      title: const Text('New waypoint'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.point.latitude.toStringAsFixed(5)}, ${widget.point.longitude.toStringAsFixed(5)}'),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: BastionWaypointStore.maxNameLength,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _description,
              maxLength: BastionWaypointStore.maxDescriptionLength,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            Wrap(
              spacing: 4,
              children: [
                for (final icon in _icons)
                  ChoiceChip(
                    label: Text(icon, style: const TextStyle(fontSize: 18)),
                    selected: _icon == icon,
                    onSelected: (_) => setState(() => _icon = icon),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Duration?>(
              initialValue: _lifetime,
              decoration: const InputDecoration(labelText: 'Expires after'),
              items: [
                for (final (label, value) in _lifetimes)
                  DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _lifetime = v),
            ),
            if (widget.localNodeNum != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Only I can edit or delete'),
                value: _locked,
                onChanged: (v) => setState(() => _locked = v),
              ),
            const Text('Shared with everyone on channel 0.', style: TextStyle(color: Colors.white60)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: name.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    MeshWaypoint(
                      id: BastionWaypointStore.newId(),
                      latitude: widget.point.latitude,
                      longitude: widget.point.longitude,
                      name: name,
                      description: _description.text.trim(),
                      icon: _icon.runes.first,
                      expires: _lifetime == null ? null : DateTime.now().toUtc().add(_lifetime!),
                      lockedTo: _locked ? widget.localNodeNum! : 0,
                    ),
                  ),
          child: const Text('Share'),
        ),
      ],
    );
  }
}
