import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/mesh_node.dart';
import '../../services/geo.dart';
import '../../services/node_archive.dart';
import '../../services/meshtastic/radio_session.dart';
import '../nodes/node_detail_page.dart';

class MeshMapPage extends StatefulWidget {
  const MeshMapPage({
    super.key,
    required this.session,
    required this.archive,
    this.active = true,
  });
  final RadioSession session;
  final NodeArchive archive;
  final bool active;
  @override
  State<MeshMapPage> createState() => _MeshMapPageState();
}

class _MeshMapPageState extends State<MeshMapPage> {
  final controller = MapController();
  int? selectedRadio;
  int? selectedNode;
  int? measureFrom;
  bool online = false;
  bool mapReady = false;
  bool tileError = false;
  int? fittedRadio;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  LatLng point(MeshNode n) => LatLng(n.latitude!, n.longitude!);
  void fit(List<MeshNode> nodes) {
    if (!mapReady || nodes.isEmpty) {
      return;
    }
    if (nodes.length == 1) {
      controller.move(point(nodes.first), 13);
    } else {
      controller.fitCamera(
        CameraFit.coordinates(
          coordinates: nodes.map(point).toList(),
          padding: const EdgeInsets.all(50),
          maxZoom: 15,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.session, widget.archive]),
    builder: (context, _) {
      final radios = {
        ...widget.archive.radios,
        if (widget.session.localNode != null) widget.session.localNode!,
      }.toList()..sort();
      final radio = radios.contains(selectedRadio)
          ? selectedRadio
          : (radios.contains(widget.session.localNode)
                ? widget.session.localNode
                : radios.firstOrNull);
      final all = radio == null ? <MeshNode>[] : widget.archive.nodesFor(radio);
      final nodes = all.where((n) => n.hasPosition).toList();
      if (widget.active &&
          mapReady &&
          nodes.isNotEmpty &&
          fittedRadio != radio) {
        fittedRadio = radio;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.active) {
            fit(nodes);
          }
        });
      }
      final selected = nodes.where((n) => n.number == selectedNode).firstOrNull;
      final origin = nodes.where((n) => n.number == measureFrom).firstOrNull;
      final distance = selected == null || origin == null
          ? null
          : nodeDistance(origin, selected);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: radio,
                    hint: const Text('Connect a radio to start'),
                    items: [
                      for (final r in radios)
                        DropdownMenuItem(
                          value: r,
                          child: Text(
                            'Radio !${r.toRadixString(16).padLeft(8, '0')}',
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      selectedRadio = value;
                      selectedNode = null;
                      measureFrom = null;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'Fit all nodes',
                  onPressed: nodes.isEmpty ? null : () => fit(nodes),
                  icon: const Icon(Icons.center_focus_strong),
                ),
              ],
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Online street map'),
            subtitle: const Text(
              'Loads visible map areas from OpenStreetMap. Saved markers work without internet.',
            ),
            value: online,
            onChanged: (v) => setState(() {
              online = v;
              tileError = false;
            }),
          ),
          if (widget.archive.error != null)
            Text(
              widget.archive.error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          if (tileError && online)
            const Text(
              'Map tiles unavailable · saved markers remain usable',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: controller,
                  options: MapOptions(
                    initialCenter: const LatLng(35.322, -83.807),
                    initialZoom: 10,
                    minZoom: 2,
                    maxZoom: 19,
                    backgroundColor: const Color(0xFF14212A),
                    onMapReady: () {
                      mapReady = true;
                      fit(nodes);
                    },
                  ),
                  children: [
                    if (online && widget.active && nodes.isNotEmpty)
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'app.bastion.bastion_meshtastic',
                        errorTileCallback: (_, _, _) {
                          if (!tileError && mounted) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() => tileError = true);
                              }
                            });
                          }
                        },
                      ),
                    MarkerLayer(
                      markers: [
                        for (final node in nodes)
                          Marker(
                            point: point(node),
                            width: 64,
                            height: 54,
                            child: Semantics(
                              label: node.displayName,
                              button: true,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => selectedNode = node.number),
                                child: Column(
                                  children: [
                                    Icon(
                                      node.number == radio
                                          ? Icons.router
                                          : Icons.location_on,
                                      color: node.number == selectedNode
                                          ? Colors.amber
                                          : const Color(0xFF18D3D3),
                                      size: 32,
                                    ),
                                    Container(
                                      color: Colors.black87,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 3,
                                      ),
                                      child: Text(
                                        node.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (nodes.isEmpty)
                  const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'No saved node positions yet.\nConnect a radio with position reports.',
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      online
                          ? '© OpenStreetMap contributors'
                          : 'Saved positions · no street tiles',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: selected == null ? 86 : 200,
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                Text(
                  '${nodes.length} positioned · ${all.length - nodes.length} without position · last known locations',
                ),
                if (selected != null) ...[
                  Text(
                    selected.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    'Position: ${selected.positionTime?.toLocal() ?? 'timestamp unknown'}',
                  ),
                  if (distance != null)
                    Text(
                      '${distance.km.toStringAsFixed(2)} km · ${distance.bearing.toStringAsFixed(0)}° from ${origin!.displayName}',
                    ),
                  if (origin != null)
                    const Text(
                      'Straight-line distance · terrain and radio coverage are not included.',
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NodeDetailPage(
                              radio: radio!,
                              node: selected,
                              archive: widget.archive,
                            ),
                          ),
                        ),
                        child: const Text('NODE HISTORY'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => measureFrom = selected.number),
                        child: const Text('MEASURE FROM HERE'),
                      ),
                      if (measureFrom != null)
                        TextButton(
                          onPressed: () => setState(() => measureFrom = null),
                          child: const Text('CLEAR MEASURE'),
                        ),
                    ],
                  ),
                ] else
                  const Text(
                    'Tap a marker for details. Select “measure from here”, then tap a second node.',
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
