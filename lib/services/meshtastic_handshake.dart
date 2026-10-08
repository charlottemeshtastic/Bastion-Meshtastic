import 'dart:async';
import 'dart:typed_data';

import 'meshtastic_connection_controller.dart';
import 'meshtastic_phoneapi_codec.dart';
import 'meshtastic_radio_session.dart';

class MeshtasticHandshake {
  MeshtasticHandshake({
    required this.session,
    required this.connection,
    this.timeout = const Duration(seconds: 20),
    this.settleDelay = const Duration(milliseconds: 100),
  });

  static const configNonce = 69420;
  static const nodeDbNonce = 69421;

  final MeshtasticRadioSession session;
  final MeshtasticConnectionController connection;
  final Duration timeout;
  final Duration settleDelay;

  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _stage1;
  Completer<void>? _stage2;
  int _heartbeatNonce = 2;
  String stage = 'idle';

  Future<void> synchronize() async {
    connection.beginSync();
    stage = 'initial configuration';
    _stage1 = Completer<void>();
    _stage2 = Completer<void>();

    await _subscription?.cancel();
    _subscription = session.incomingEnvelopes.listen(
      _handleEnvelope,
      onError: (Object error) {
        connection.fail(error);
        _completeError(error);
      },
    );

    try {
      await session.send(MeshtasticPhoneApiCodec.wantConfig(configNonce));
      await _stage1!.future.timeout(timeout,
        onTimeout: () => throw TimeoutException('No configComplete(69420) during $stage', timeout));
      stage = 'node database synchronization';

      await Future<void>.delayed(settleDelay);
      await session.send(
        MeshtasticPhoneApiCodec.heartbeat(_heartbeatNonce++),
      );
      await Future<void>.delayed(settleDelay);

      await session.send(MeshtasticPhoneApiCodec.wantConfig(nodeDbNonce));
      await _stage2!.future.timeout(timeout,
        onTimeout: () => throw TimeoutException('No configComplete(69421) during $stage', timeout));
      stage = 'ready';
      connection.markReady();
    } catch (error) {
      connection.fail(error);
      rethrow;
    }
  }

  void _handleEnvelope(Uint8List bytes) {
    final envelope = MeshtasticPhoneApiCodec.decodeFromRadio(bytes);

    if (envelope.rebooted) {
      final error = StateError('Meshtastic radio rebooted during handshake.');
      connection.fail(error);
      _completeError(error);
      return;
    }

    final completeId = envelope.configCompleteId;
    if (completeId == configNonce && !(_stage1?.isCompleted ?? true)) {
      _stage1!.complete();
    } else if (completeId == nodeDbNonce &&
        !(_stage2?.isCompleted ?? true)) {
      _stage2!.complete();
    }
  }

  void _completeError(Object error) {
    if (!(_stage1?.isCompleted ?? true)) _stage1!.completeError(error);
    if (!(_stage2?.isCompleted ?? true)) _stage2!.completeError(error);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
