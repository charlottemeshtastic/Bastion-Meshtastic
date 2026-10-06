import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/mesh_node.dart';
import '../../models/telemetry_sample.dart';
import '../../services/node_archive.dart';

class NodeDetailPage extends StatelessWidget {
  const NodeDetailPage({
    super.key,
    required this.radio,
    required this.node,
    required this.archive,
  });
  final int radio;
  final MeshNode node;
  final NodeArchive archive;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(node.displayName)),
    body: AnimatedBuilder(
      animation: archive,
      builder: (context, _) {
        final current =
            archive
                .nodesFor(radio)
                .where((n) => n.number == node.number)
                .firstOrNull ??
            node;
        final samples = archive.samplesFor(radio, node.number);
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(current.id, style: Theme.of(context).textTheme.titleLarge),
            Text('Last heard: ${current.lastHeard?.toLocal() ?? 'unknown'}'),
            Text(
              current.powered
                  ? 'External power reported'
                  : 'Battery: ${current.battery ?? 'unknown'}${current.battery == null ? '' : '%'}',
            ),
            if (current.hasPosition) ...[
              const SizedBox(height: 12),
              Text(
                'Last known position: ${current.latitude!.toStringAsFixed(5)}, ${current.longitude!.toStringAsFixed(5)}',
              ),
              Text(
                'Position timestamp: ${current.positionTime?.toLocal() ?? 'unknown'}',
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('COPY COORDINATES'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: '${current.latitude}, ${current.longitude}',
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Coordinates copied')),
                    );
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'RECEIVED TELEMETRY',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Measurements collected while connected. Gaps mean no reading was received. '
              'Signal values describe reception at your radio, not end-to-end link quality.',
            ),
            if (samples.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No live measurements saved for this node yet.'),
              ),
            if (samples.isNotEmpty) ...[
              _Trend(
                title: 'Battery',
                unit: '%',
                samples: samples,
                value: (s) => s.battery?.toDouble(),
              ),
              _Trend(
                title: 'Receive SNR',
                unit: 'dB',
                samples: samples,
                value: (s) => s.snr,
              ),
              const SizedBox(height: 12),
              const Text(
                'LATEST READINGS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final sample in samples.reversed.take(20))
                Card(
                  child: ListTile(
                    title: Text(sample.time.toLocal().toString()),
                    subtitle: Text(
                      [
                        if (sample.battery != null)
                          '${sample.battery}% battery',
                        if (sample.powered == true) 'External power',
                        if (sample.voltage != null)
                          '${sample.voltage!.toStringAsFixed(2)} V',
                        if (sample.snr != null)
                          'SNR ${sample.snr!.toStringAsFixed(1)} dB',
                        if (sample.rssi != null) 'RSSI ${sample.rssi} dBm',
                        if (sample.channelUtilization != null)
                          'Channel ${sample.channelUtilization!.toStringAsFixed(1)}%',
                        if (sample.airUtilization != null)
                          'TX airtime ${sample.airUtilization!.toStringAsFixed(1)}%',
                      ].join(' · '),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Local history: up to 30 days and 4,000 readings across all radios.',
            ),
          ],
        );
      },
    ),
  );
}

class _Trend extends StatelessWidget {
  const _Trend({
    required this.title,
    required this.unit,
    required this.samples,
    required this.value,
  });
  final String title;
  final String unit;
  final List<TelemetrySample> samples;
  final double? Function(TelemetrySample) value;
  @override
  Widget build(BuildContext context) {
    final points = [
      for (final s in samples)
        if (value(s) != null && value(s)!.isFinite) (s.time, value(s)!),
    ];
    if (points.isEmpty) {
      return Text('$title: no readings');
    }
    final values = points.map((p) => p.$2);
    final low = values.reduce(min);
    final high = values.reduce(max);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title · latest ${points.last.$2.toStringAsFixed(1)} $unit'),
            Text(
              'Range ${low.toStringAsFixed(1)}–${high.toStringAsFixed(1)} $unit · ${points.length} readings',
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              width: double.infinity,
              child: CustomPaint(
                painter: _Plot(points, Theme.of(context).colorScheme.primary),
              ),
            ),
            Text(
              '${points.first.$1.toLocal()} → ${points.last.$1.toLocal()}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Plot extends CustomPainter {
  _Plot(this.points, this.color);
  final List<(DateTime, double)> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final low = points.map((p) => p.$2).reduce(min);
    final high = points.map((p) => p.$2).reduce(max);
    final span = max(1.0, high - low);
    final start = points.first.$1.millisecondsSinceEpoch;
    final duration = max(1, points.last.$1.millisecondsSinceEpoch - start);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    final grid = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = 5 + i * (size.height - 10) / 2;
      canvas.drawLine(Offset(5, y), Offset(size.width - 5, y), grid);
    }
    // Individual points show irregular observation spacing without implying
    // measurements during radio disconnects or silent intervals.
    for (final p in points) {
      final x =
          5 +
          (p.$1.millisecondsSinceEpoch - start) / duration * (size.width - 10);
      final y = high == low
          ? size.height / 2
          : 5 + (high - p.$2) / span * (size.height - 10);
      canvas.drawCircle(Offset(x, y), 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Plot old) => true;
}
