import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'radio_transport.dart';

const meshtasticServiceUuid = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
const _toRadioUuid = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
const _fromRadioUuid = '2c55e69e-4993-11ed-b878-0242ac120002';
const _fromNumUuid = 'ed9da18c-a800-4f66-a670-aa7547e34453';

class BleRadioTransport implements RadioTransport {
  BleRadioTransport(this.device);
  final BluetoothDevice device;
  final _frames = StreamController<List<int>>.broadcast();
  final _disconnections = StreamController<void>.broadcast();
  @override
  Stream<List<int>> get frames => _frames.stream;
  @override
  Stream<void> get disconnections => _disconnections.stream;
  BluetoothCharacteristic? _toRadio;
  BluetoothCharacteristic? _fromRadio;
  StreamSubscription<List<int>>? _notifications;
  StreamSubscription<BluetoothConnectionState>? _state;
  Timer? _poll;
  bool _closed = false;
  bool _connected = false;
  bool _reading = false;
  bool _readAgain = false;

  @override
  Future<void> open() async {
    if (_closed) {
      throw StateError('Transport is closed.');
    }
    _state = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        _connected = true;
      } else if (_connected && !_closed) {
        _connected = false;
        _disconnections.add(null);
      }
    });
    // The project's current use is personal/noncommercial. See third-party
    // notices before distributing commercially with FlutterBluePlus 2.x.
    await device.connect(license: License.free, timeout: const Duration(seconds: 25));
    if (_closed) {
      await device.disconnect();
      throw StateError('Connection was cancelled.');
    }
    final services = await device.discoverServices();
    final matching = services.where((s) => s.uuid == Guid(meshtasticServiceUuid));
    if (matching.isEmpty) {
      throw StateError('This Bluetooth device does not expose the Meshtastic service.');
    }
    final characteristics = matching.first.characteristics;
    BluetoothCharacteristic requiredCharacteristic(String uuid) {
      final found = characteristics.where((c) => c.uuid == Guid(uuid));
      if (found.isEmpty) {
        throw StateError('Radio is missing a required Meshtastic characteristic.');
      }
      return found.first;
    }
    _toRadio = requiredCharacteristic(_toRadioUuid);
    _fromRadio = requiredCharacteristic(_fromRadioUuid);
    final fromNum = requiredCharacteristic(_fromNumUuid);
    if (!_toRadio!.properties.write || !_fromRadio!.properties.read ||
        !(fromNum.properties.notify || fromNum.properties.indicate)) {
      throw StateError('Radio characteristics do not support the Meshtastic BLE API.');
    }
    _notifications = fromNum.onValueReceived.listen((_) => unawaited(_drain()));
    await fromNum.setNotifyValue(true);
    if (_closed) {
      return;
    }
    // Poll is a fallback for missed notifications and early config packets.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_drain()));
  }

  Future<void> _drain() async {
    if (_closed || _fromRadio == null) {
      return;
    }
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    try {
      do {
        _readAgain = false;
        // Drain bounded batches to avoid starving disconnect/control operations.
        for (var i = 0; i < 256 && !_closed; i++) {
          final value = await _fromRadio!.read();
          if (_closed || value.isEmpty) {
            break;
          }
          _frames.add(value);
          if (i == 255) {
            _readAgain = true;
          }
        }
      } while (_readAgain && !_closed);
    } catch (e) {
      if (!_closed) {
        _frames.addError(e);
      }
    } finally {
      _reading = false;
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (_closed || _toRadio == null) {
      throw StateError('Radio is not connected.');
    }
    // One ToRadio message per GATT write; never split protobufs into frames.
    await _toRadio!.write(bytes, withoutResponse: false, allowLongWrite: true);
    unawaited(_drain());
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _poll?.cancel();
    await _notifications?.cancel();
    await _state?.cancel();
    try {
      await device.disconnect();
    } finally {
      await _frames.close();
      await _disconnections.close();
    }
  }
}
