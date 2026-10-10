import 'package:bastion/services/bastion_background_service.dart';
import 'package:bastion/services/meshtastic_radio_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingKeeper implements BastionBackgroundKeeper {
  final events = <String>[];

  @override
  Future<void> keepAlive({required String radioName, required bool reconnecting}) async =>
      events.add('keep $radioName${reconnecting ? ' reconnecting' : ''}');

  @override
  Future<void> release() async => events.add('release');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manual disconnect releases the background service', () async {
    final keeper = RecordingKeeper();
    final radio = MeshtasticRadioCoordinator(background: keeper);
    await radio.disconnect();
    expect(keeper.events, contains('release'));
    radio.dispose();
  });

  test('foreground service is a no-op off Android', () async {
    final service = BastionForegroundService();
    await service.keepAlive(radioName: 'Trail', reconnecting: false);
    await service.release();
  });
}
