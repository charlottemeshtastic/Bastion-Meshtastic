import 'package:flutter/material.dart';
import '../../services/field/offline_maps.dart';

class OfflineMapsPage extends StatelessWidget {
  const OfflineMapsPage({super.key, required this.maps});
  final OfflineMaps maps;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('OFFLINE MAP PACK')),
    body: AnimatedBuilder(
      animation: maps,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Import a ZIP containing PNG tiles at z/x/y.png and metadata.json at its root. '
            'Use maps you have permission to store offline. Bastion does not bulk-download map providers.',
          ),
          const SizedBox(height: 12),
          const SelectableText(
            'metadata.json example:\n{\n  "name": "Graham County",\n  "attribution": "Map data provider and license",\n  "latitude": 35.322,\n  "longitude": -83.807,\n  "minZoom": 8,\n  "maxZoom": 15\n}',
          ),
          const SizedBox(height: 12),
          const Text(
            'One imported pack at a time; XYZ tile numbering, PNG tiles of 256 or 512 pixels, '
            'zoom 0–19, up to 10,000 tiles, ZIP up to 128 MiB and extracted data up to 256 MiB. '
            'MBTiles, PMTiles and GPX are not supported in this version. Missing tiles remain blank; no network fallback.',
          ),
          if (maps.pack != null)
            Card(
              child: ListTile(
                title: Text(maps.pack!.name),
                subtitle: Text(
                  '${maps.pack!.tiles} tiles · zoom ${maps.pack!.minZoom}–${maps.pack!.maxZoom}\n${maps.pack!.attribution}',
                ),
              ),
            ),
          if (maps.busy) const LinearProgressIndicator(),
          if (maps.error != null)
            Text(
              maps.error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          FilledButton.icon(
            onPressed: maps.busy || maps.failedLoad || !maps.backend.supported
                ? null
                : maps.importPack,
            icon: const Icon(Icons.folder_open),
            label: const Text('IMPORT MAP PACK ZIP'),
          ),
          if (maps.pack != null)
            TextButton(
              onPressed: maps.busy || maps.failedLoad
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Remove offline tiles?'),
                          content: const Text(
                            'Saved nodes and measured observations are kept.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('CANCEL'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('REMOVE'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await maps.clear();
                      }
                    },
              child: const Text('REMOVE MAP PACK'),
            ),
        ],
      ),
    ),
  );
}
