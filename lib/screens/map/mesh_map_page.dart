import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/mesh_node.dart';
import '../../services/geo.dart';
import '../../services/node_archive.dart';
import '../../services/meshtastic/radio_session.dart';
import '../nodes/node_detail_page.dart';
import '../../services/field/offline_maps.dart';
import '../../services/field/coverage.dart';
import 'offline_maps_page.dart';

class MeshMapPage extends StatefulWidget {
  const MeshMapPage({
    super.key,
    required this.session,
    required this.archive,
    this.active = true,
    this.offlineMaps,
    this.coverage,
  });
  final RadioSession session;
  final NodeArchive archive;
  final bool active;
  final OfflineMaps? offlineMaps;
  final CoverageRecorder? coverage;
  @override
  State<MeshMapPage> createState() => _MeshMapPageState();
}

class _MeshMapPageState extends State<MeshMapPage> {
  final controller = MapController();
  int? selectedRadio;
  int? selectedNode;
  int? measureFrom;
  bool online = false;
  bool useOffline = true;
  int? imageRevision;
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
    animation: Listenable.merge([
      widget.session,
      widget.archive,
      if (widget.offlineMaps != null) widget.offlineMaps!,
      if (widget.coverage != null) widget.coverage!,
    ]),
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
      final pack = useOffline && !online ? widget.offlineMaps?.pack : null;
      final measured =
          widget.coverage?.points.where((p) => p.radio == radio).toList() ??
          <CoveragePoint>[];
      if (imageRevision != widget.offlineMaps?.revision) {
        imageRevision = widget.offlineMaps?.revision;
        PaintingBinding.instance.imageCache.clear();
      }
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
              if (v) {
                useOffline = false;
              }
              tileError = false;
            }),
          ),
          if (widget.offlineMaps != null)
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('OFFLINE MAP PACK'),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              OfflineMapsPage(maps: widget.offlineMaps!),
                        ),
                      );
                      if (mounted && widget.offlineMaps!.pack != null) {
                        setState(() {
                          useOffline = true;
                          online = false;
                          tileError = false;
                        });
                        final imported = widget.offlineMaps!.pack!;
                        if (mapReady) {
                          controller.move(
                            LatLng(imported.latitude, imported.longitude),
                            imported.minZoom.toDouble(),
                          );
                        }
                      }
                    },
                  ),
                ),
                if (widget.offlineMaps!.pack != null)
                  IconButton(
                    tooltip: 'Show offline pack',
                    icon: const Icon(Icons.offline_pin),
                    onPressed: () => setState(() {
                      useOffline = true;
                      online = false;
                      tileError = false;
                      final p = widget.offlineMaps!.pack!;
                      if (mapReady) {
                        controller.move(
                          LatLng(p.latitude, p.longitude),
                          p.minZoom.toDouble(),
                        );
                      }
                    }),
                  ),
                if (measured.isNotEmpty)
                  IconButton(
                    tooltip: 'Fit measured receiver points',
                    icon: const Icon(Icons.route),
                    onPressed: !mapReady
                        ? null
                        : () => controller.fitCamera(
                            CameraFit.coordinates(
                              coordinates: measured
                                  .map(
                                    (p) => LatLng(
                                      p.location.latitude,
                                      p.location.longitude,
                                    ),
                                  )
                                  .toList(),
                              padding: const EdgeInsets.all(40),
                              maxZoom: 15,
                            ),
                          ),
                  ),
              ],
            ),
          if (tileError && pack != null)
            const Text(
              'Some offline tiles are unavailable · no network fallback',
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
                    minZoom: 0,
                    maxZoom: 19,
                    backgroundColor: const Color(0xFF14212A),
                    onMapReady: () {
                      mapReady = true;
                      fit(nodes);
                    },
                  ),
                  children: [
                    if (pack != null && widget.active)
                      TileLayer(
                        key: ValueKey(
                          'offline-${widget.offlineMaps!.revision}',
                        ),
                        urlTemplate: '${pack.path}/{z}/{x}/{y}.png',
                        tileProvider: FileTileProvider(),
                        minNativeZoom: pack.minZoom,
                        maxNativeZoom: pack.maxZoom,
                        minZoom: pack.minZoom.toDouble(),
                        maxZoom: pack.maxZoom.toDouble(),
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
                        for (final p in measured)
                          Marker(
                            point: LatLng(
                              p.location.latitude,
                              p.location.longitude,
                            ),
                            width: 30,
                            height: 30,
                            child: GestureDetector(
                              onTap: () => showModalBottomSheet<void>(
                                context: context,
                                builder: (context) => Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Text(
                                    'MEASURED RECEIVER POINT\n${p.time.toLocal()}\n'
                                    'Packet from !${p.node.toRadixString(16).padLeft(8, '0')}\n'
                                    'RX SNR: ${p.snr ?? 'not present'} dB · RX RSSI: ${p.rssi ?? 'not present'} dBm\n'
                                    'Phone fix: ${p.location.time.toLocal()} · ±${p.location.accuracy.toStringAsFixed(0)} m\n'
                                    'Last RF hop may be a relay. This point does not prove continuous coverage.',
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.circle,
                                color: Colors.amber,
                                size: 16,
                              ),
                            ),
                          ),
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
                if (nodes.isEmpty && pack == null && measured.isEmpty)
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
                          : pack != null
                          ? pack.attribution
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
                  '${nodes.length} positioned · ${all.length - nodes.length} without position · ${measured.length} receiver observations',
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
