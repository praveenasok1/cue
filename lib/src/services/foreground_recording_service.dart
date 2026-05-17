import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart';

void configureForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'cue_recording',
      channelName: 'CUE recording',
      channelDescription: 'Shows when CUE is recording an earphone session.',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

@pragma('vm:entry-point')
void cueForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(CueForegroundTaskHandler());
}

class CueForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain({
      'type': 'recording_service_started',
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'CUE is recording',
      notificationText:
          'Earphone session active since ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    FlutterForegroundTask.sendDataToMain({
      'type': 'recording_service_stopped',
      'timestamp': timestamp.toIso8601String(),
      'timeout': isTimeout,
    });
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}

class ForegroundRecordingService {
  bool get _supportsForegroundService {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> ensurePermissions() async {
    try {
      final notificationPermission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }

    if (_supportsForegroundService &&
        !await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  Future<void> start() async {
    await ensurePermissions();
    if (!_supportsForegroundService) return;

    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
        return;
      }

      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: 'CUE is recording',
        notificationText: 'Earphone session active',
        notificationInitialRoute: '/',
        callback: cueForegroundTaskCallback,
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> stop() async {
    if (!_supportsForegroundService) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
