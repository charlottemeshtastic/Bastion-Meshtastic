import 'dart:async';
import 'dart:typed_data';

/// Transport-agnostic byte channel for the Meshtastic PhoneAPI.
///
/// Each inbound item is one encoded FromRadio protobuf envelope and each
/// outbound write is one encoded ToRadio protobuf envelope. Transport-specific
/// framing belongs in implementations, not in messaging or UI code.
abstract interface class MeshtasticRadioTransport {
  Stream<Uint8List> get fromRadio;

  bool get isConnected;

  Future<void> connect();

  Future<void> sendToRadio(Uint8List envelope);

  Future<void> disconnect();
}

/// Stable Meshtastic BLE GATT identifiers used by the PhoneAPI.
///
/// BLE carries one protobuf envelope per fromradio read / toradio write. The
/// fromnum characteristic is a wake signal telling clients to drain fromradio.
abstract final class MeshtasticBleGatt {
  static const service = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
  static const toRadio = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
  static const fromRadio = '2c55e69e-4993-11ed-b878-0242ac120002';
  static const fromNum = 'ed9da18c-a800-4f66-a670-aa7547e34453';
  static const logRadio = '5a3d6e49-06e6-4423-9944-e9de8cdf9547';
  static const legacyLogRadio = '6c6fd238-78fa-436b-aacf-15c5be1ef2e2';
}
