import 'dart:async';
import 'dart:typed_data';

import 'meshtastic_connection_controller.dart';
import 'meshtastic_radio_transport.dart';

/// Coordinates a transport with Bastion's app-level connection lifecycle.
///
/// Protobuf decoding intentionally lives above this boundary. That keeps BLE,
/// TCP and future USB transports interchangeable.
class MeshtasticRadioSession {
  MeshtasticRadioSession({
    required this.transport,
    required this.connection,
  });

  final MeshtasticRadioTransport transport;
  final MeshtasticConnectionController connection;

  StreamSubscription<Uint8List>? _subscription;
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get incomingEnvelopes => _incoming.stream;

  Future<void> connect({required String deviceName}) async {
    connection.beginConnect(deviceName);
    try {
      // Subscribe before opening BLE. The transport can drain FromRadio as
      // part of connect(), and a broadcast stream would otherwise drop those
      // envelopes before the session is listening.
      await _subscription?.cancel();
      _subscription = transport.fromRadio.listen(
        _incoming.add,
        onError: connection.fail,
      );

      await transport.connect();
      connection.markConnected();
    } catch (error) {
      await _subscription?.cancel();
      _subscription = null;
      connection.fail(error);
      rethrow;
    }
  }

  Future<void> send(Uint8List toRadioEnvelope) async {
    if (!transport.isConnected) {
      throw StateError('Cannot send ToRadio while transport is disconnected.');
    }
    await transport.sendToRadio(toRadioEnvelope);
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await transport.disconnect();
    } finally {
      connection.disconnect();
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _incoming.close();
  }
}
