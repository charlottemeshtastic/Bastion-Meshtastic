import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Transport-agnostic byte channel for the Meshtastic PhoneAPI.
///
/// Each inbound item is one encoded FromRadio protobuf envelope and each
/// outbound write is one encoded ToRadio protobuf envelope.
abstract interface class MeshtasticRadioTransport {
  Stream<Uint8List> get fromRadio;
  bool get isConnected;
  Future<void> connect();
  Future<void> sendToRadio(Uint8List envelope);
  Future<void> disconnect();
}

/// Stable Meshtastic BLE GATT identifiers used by the PhoneAPI.
abstract final class MeshtasticBleGatt {
  static const service = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
  static const toRadio = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
  static const fromRadio = '2c55e69e-4993-11ed-b878-0242ac120002';
  static const fromNum = 'ed9da18c-a800-4f66-a670-aa7547e34453';
  static const logRadio = '5a3d6e49-06e6-4423-9944-e9de8cdf9547';
  static const legacyLogRadio = '6c6fd238-78fa-436b-aacf-15c5be1ef2e2';
}

/// Concrete Meshtastic PhoneAPI transport over Bluetooth LE.
///
/// Meshtastic's FromNum notification is a wake-up signal. Every wake drains
/// FromRadio until the mailbox returns an empty value. ToRadio uses
/// acknowledged writes.
class MeshtasticUniversalBleTransport implements MeshtasticRadioTransport {
  MeshtasticUniversalBleTransport({required this.deviceId});

  final String deviceId;
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();

  StreamSubscription<Uint8List>? _fromNumSubscription;
  bool _connected = false;
  bool _draining = false;
  bool _drainAgain = false;

  @override
  Stream<Uint8List> get fromRadio => _incoming.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    if (_connected) return;

    try {
      await UniversalBle.stopScan();
    } catch (_) {
      // There may be no active scan.
    }

    try {
      await UniversalBle.connect(deviceId).timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Native BLE connect did not complete for $deviceId',
        ),
      );
    } catch (error) {
      throw StateError('BLE connection stage failed for $deviceId: $error');
    }
    try {
      List<BleService> services;
      try {
        services = await UniversalBle.discoverServices(deviceId).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('GATT service discovery timed out'),
        );
      } catch (error) {
        throw StateError('BLE service discovery failed: $error');
      }
      final hasMeshtastic = services.any(
        (service) => service.uuid.toLowerCase() == MeshtasticBleGatt.service,
      );
      if (!hasMeshtastic) {
        throw StateError('Selected device does not expose the Meshtastic BLE service.');
      }

      try {
        await UniversalBle.requestMtu(deviceId, 512);
      } catch (_) {
        // MTU negotiation is an optimization; the platform may negotiate it.
      }

      _fromNumSubscription = UniversalBle.characteristicValueStream(
        deviceId,
        MeshtasticBleGatt.fromNum,
      ).listen(
        (_) => _scheduleDrain(),
        onError: _incoming.addError,
      );

      try {
        await UniversalBle.subscribeNotifications(
          deviceId,
          MeshtasticBleGatt.service,
          MeshtasticBleGatt.fromNum,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('FromNum subscription timed out'),
        );
      } catch (error) {
        throw StateError('BLE FromNum notification subscription failed: $error');
      }

      _connected = true;
      await _drainMailbox();
    } catch (_) {
      await UniversalBle.disconnect(deviceId);
      rethrow;
    }
  }

  @override
  Future<void> sendToRadio(Uint8List envelope) async {
    if (!_connected) {
      throw StateError('Meshtastic BLE transport is not connected.');
    }
    try {
      await UniversalBle.write(
        deviceId,
        MeshtasticBleGatt.service,
        MeshtasticBleGatt.toRadio,
        envelope,
        withoutResponse: false,
      );
    } catch (error) {
      throw StateError('BLE ToRadio write failed: $error');
    }

    // A notification can be missed or arrive before the mailbox read starts.
    // Poll after each command as a fallback; FromNum remains the primary signal.
    unawaited(_pollAfterWrite());
  }

  Future<void> _pollAfterWrite() async {
    for (final delay in <Duration>[
      const Duration(milliseconds: 200),
      const Duration(seconds: 1),
      const Duration(seconds: 3),
    ]) {
      await Future<void>.delayed(delay);
      if (!_connected) return;
      _scheduleDrain();
    }
  }

  void _scheduleDrain() {
    if (!_connected) return;
    if (_draining) {
      _drainAgain = true;
      return;
    }
    unawaited(_drainMailbox());
  }

  Future<void> _drainMailbox() async {
    if (_draining || !_connected) return;
    _draining = true;
    try {
      do {
        _drainAgain = false;
        while (_connected) {
          final bytes = await UniversalBle.read(
            deviceId,
            MeshtasticBleGatt.service,
            MeshtasticBleGatt.fromRadio,
          );
          if (bytes.isEmpty) break;
          _incoming.add(bytes);
        }
      } while (_drainAgain && _connected);
    } catch (error, stackTrace) {
      _incoming.addError(error, stackTrace);
    } finally {
      _draining = false;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _fromNumSubscription?.cancel();
    _fromNumSubscription = null;
    try {
      await UniversalBle.unsubscribe(
        deviceId,
        MeshtasticBleGatt.service,
        MeshtasticBleGatt.fromNum,
      );
    } catch (_) {
      // Best effort when the peripheral already disappeared.
    }
    try {
      await UniversalBle.disconnect(deviceId);
    } catch (_) {
      // Treat an already-lost peripheral as disconnected.
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _incoming.close();
  }
}
