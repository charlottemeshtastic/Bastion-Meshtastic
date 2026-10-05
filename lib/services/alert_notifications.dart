import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'automations/automation_engine.dart';

abstract class AlertNotificationBackend {
  bool get supported;
  Future<void> initialize();
  Future<bool> allowed();
  Future<bool> requestPermission();
  Future<void> show(int id, String title, String body);
}

class AndroidAlertBackend implements AlertNotificationBackend {
  AndroidAlertBackend({this.onOpen});
  final VoidCallback? onOpen;
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<void> initialize() async {
    if (initialized) {
      return;
    }
    final success = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_bastion'),
      ),
      onDidReceiveNotificationResponse: (_) => onOpen?.call(),
    );
    if (success != true) {
      throw StateError('Notification initialization failed');
    }
    initialized = true;
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      onOpen?.call();
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  @override
  Future<bool> allowed() async =>
      await android?.areNotificationsEnabled() == true;
  @override
  Future<bool> requestPermission() async =>
      await android?.requestNotificationsPermission() == true;
  @override
  Future<void> show(int id, String title, String body) => plugin.show(
    id: id,
    title: title,
    body: body,
    payload: 'automations',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'bastion_local_alerts_v1',
        'Bastion mesh alerts',
        channelDescription:
            'Alerts from local mesh rules while connected in the foreground',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_bastion',
        visibility: NotificationVisibility.private,
      ),
    ),
  );
}

/// Opt-in notifications for new live alerts only. This does not keep BLE alive
/// or schedule background rule evaluation.
class AlertNotifications extends ChangeNotifier {
  AlertNotifications({AlertNotificationBackend? backend, VoidCallback? onOpen})
    : backend = backend ?? AndroidAlertBackend(onOpen: onOpen);
  static const storageKey = 'bastion.android.alerts.v1';
  final AlertNotificationBackend backend;
  bool loading = true;
  bool saving = false;
  bool enabled = false;
  String? error;
  bool _disposed = false;
  bool get supported => backend.supported;
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(storageKey) == true && supported) {
        await backend.initialize();
        enabled = await backend.allowed();
        if (!enabled) {
          error =
              'Android notification permission is disabled. Enable it again to receive alerts.';
        }
      }
    } catch (_) {
      error =
          'Android alerts could not be initialized. In-app alert history remains available.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (loading || saving || !supported || _disposed) {
      return;
    }
    saving = true;
    error = null;
    _notify();
    try {
      if (value) {
        await backend.initialize();
        if (!await backend.requestPermission() || !await backend.allowed()) {
          error =
              'Android did not grant notification permission. Check Bastion notification settings on your phone.';
          return;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(storageKey, value)) {
        throw StateError('Save failed');
      }
      enabled = value;
    } catch (_) {
      error =
          'Notification preference could not be saved. In-app alerts are still available.';
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> showAlert(AutomationAlert alert) async {
    if (!enabled || loading || _disposed) {
      return;
    }
    try {
      if (!await backend.allowed()) {
        enabled = false;
        error =
            'Android notifications are blocked. Live alerts are still saved in AUTO.';
        _notify();
        return;
      }
      if (!enabled || _disposed) {
        return;
      }
      final key = '${alert.radioId}:${alert.ruleId}:${alert.nodeId}';
      var id = 2166136261;
      for (final code in key.codeUnits) {
        id = ((id ^ code) * 16777619) & 0x7fffffff;
      }
      await backend.show(id, 'Bastion mesh alert', alert.message);
    } catch (_) {
      error =
          'An Android notification could not be shown. The alert remains in AUTO.';
      _notify();
    }
  }

  Future<void> test() => showAlert(
    AutomationAlert(
      'notification-test',
      'test',
      'Test alert · no radio event or automation action',
      DateTime.now(),
    ),
  );
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
