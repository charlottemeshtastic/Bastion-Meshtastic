import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'services/bastion_geo.dart';
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
                options: const MapOptions(
                  initialCenter: LatLng(39.5, -98.35),
                  initialZoom: 3,
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'org.backcountrysignal.bastion',
                    maxNativeZoom: 19,
                  ),
                  MarkerLayer(
                    markers: [
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
                                : '${placed.length} of ${widget.radio.nodes.length} nodes placed',
                          ),
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
