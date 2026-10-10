import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows a phone notification for an incoming mesh message.
abstract interface class BastionMessageAlerts {
  Future<void> show({
    required int packetId,
    required String sender,
    required String text,
    required bool isDirect,
    required int channel,
  });
}

/// Android notifications for messages that arrive while Bastion is not in
/// the foreground. Direct messages and channel messages use separate
/// channels so people can mute one without the other in Android settings.
class BastionLocalMessageAlerts implements BastionMessageAlerts {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static const _direct = AndroidNotificationDetails(
    'bastion_direct_messages',
    'Direct messages',
    channelDescription: 'Messages sent to you on the mesh.',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );

  static const _channel = AndroidNotificationDetails(
    'bastion_channel_messages',
    'Channel messages',
    channelDescription: 'Messages on your mesh channels.',
    importance: Importance.defaultImportance,
    category: AndroidNotificationCategory.message,
  );

  Future<bool> _initialize() async {
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      return ok ?? false;
    } catch (error) {
      debugPrint('Bastion message alerts unavailable: $error');
      return false;
    }
  }

  @override
  Future<void> show({
    required int packetId,
    required String sender,
    required String text,
    required bool isDirect,
    required int channel,
  }) async {
    if (!_supported) return;
    if (!await (_ready ??= _initialize())) return;
    try {
      await _plugin.show(
        id: packetId & 0x7fffffff,
        title: isDirect ? sender : '$sender • channel $channel',
        body: text,
        notificationDetails: NotificationDetails(android: isDirect ? _direct : _channel),
      );
    } catch (error) {
      debugPrint('Bastion message alert failed: $error');
    }
  }
}
