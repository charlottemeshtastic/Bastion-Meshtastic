import 'dart:math' as math;

/// Computes metrics only from measured samples, never simulated RSSI/SNR.
abstract final class BastionSignalStatistics {
  static double? mean(Iterable<double> values) {
    final samples = values.where((v) => v.isFinite).toList();
    if (samples.isEmpty) return null;
    return samples.reduce((a, b) => a + b) / samples.length;
  }

  static double? standardDeviation(Iterable<double> values) {
    final samples = values.where((v) => v.isFinite).toList();
    final average = mean(samples);
    if (average == null) return null;
    return math.sqrt(samples.map((v) => math.pow(v - average, 2)).reduce((a, b) => a + b) / samples.length);
  }
}
