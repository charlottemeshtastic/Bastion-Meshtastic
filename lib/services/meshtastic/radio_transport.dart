/// Carries complete protobuf frames; BLE packets do not use serial framing.
abstract class RadioTransport {
  Stream<List<int>> get frames;
  Stream<void> get disconnections;
  Future<void> open();
  Future<void> write(List<int> bytes);
  Future<void> close();
}
