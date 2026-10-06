import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/field/coverage.dart';
import '../../services/meshtastic/radio_session.dart';

class CoveragePanel extends StatelessWidget {
  const CoveragePanel({super.key, required this.recorder});
  final CoverageRecorder recorder;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([recorder, recorder.session]),
    builder: (context, _) {
      final busy =
          recorder.loading || recorder.loadFailed || recorder.capturing;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MEASURED FIELD OBSERVATIONS',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${recorder.points.length}/2000 saved · ${recorder.recording ? 'recording at captured receiver point' : 'paused'}',
              ),
              const Text(
                'Capture your phone location, hold still, and receive radio packets. '
                'Only fresh received SNR/RSSI readings are recorded. Each fix expires after 2 minutes; movement is not tracked. '
                'Readings may be from the last relay hop, not a direct link to the original sender. '
                'MQTT traffic is excluded. Unmeasured places have unknown coverage.',
              ),
              if (recorder.fix != null)
                Text(
                  'Phone fix: ${recorder.fix!.time.toLocal()} · ±${recorder.fix!.accuracy.toStringAsFixed(0)} m',
                ),
              if (recorder.capturing) const LinearProgressIndicator(),
              if (recorder.error != null)
                Text(
                  recorder.error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed:
                        busy ||
                            !recorder.backend.supported ||
                            recorder.session.status != RadioStatus.ready
                        ? null
                        : recorder.start,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      recorder.capturing
                          ? 'CAPTURING LOCATION…'
                          : 'CAPTURE RECEIVER POINT',
                    ),
                  ),
                  if (recorder.recording)
                    TextButton(
                      onPressed: recorder.stop,
                      child: const Text('STOP RECORDING'),
                    ),
                  if (recorder.points.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: recorder.csv()),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Measured observations CSV copied, including receiver coordinates',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('COPY MEASUREMENTS CSV'),
                    ),
                  if (recorder.points.isNotEmpty)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text(
                                    'Clear measured observations?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('CANCEL'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('CLEAR'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await recorder.clear();
                              }
                            },
                      child: const Text('CLEAR MEASUREMENTS'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
