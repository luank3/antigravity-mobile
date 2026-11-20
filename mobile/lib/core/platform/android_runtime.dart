import 'dart:io';

import 'package:flutter/services.dart';

/// Abstraction over native Android runtime capabilities (foreground keepalive
/// service, partial WakeLock/screen-on flag, and local alert notifications).
abstract class AndroidRuntime {
  Future<bool> requestNotificationPermission();

  Future<void> startForegroundService({
    required String title,
    required String body,
    bool holdWakeLock = false,
  });

  Future<void> stopForegroundService();

  Future<void> setKeepScreenOn(bool enabled);

  Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
  });
}

/// MethodChannel implementation backed by [MainActivity] on Android.
class MethodChannelAndroidRuntime implements AndroidRuntime {
  static const _channel = MethodChannel('xyz.luaan.antigravitymobile/android_runtime');

  @override
  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> startForegroundService({
    required String title,
    required String body,
    bool holdWakeLock = false,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startForegroundService', {
        'title': title,
        'body': body,
        'holdWakeLock': holdWakeLock,
      });
    } catch (_) {}
  }

  @override
  Future<void> stopForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopForegroundService');
    } catch (_) {}
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {'enabled': enabled});
    } catch (_) {}
  }

  @override
  Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('showAlertNotification', {
        'id': id,
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }
}

/// Safe no-op implementation used in headless tests and non-Android hosts.
class NoopAndroidRuntime implements AndroidRuntime {
  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> startForegroundService({
    required String title,
    required String body,
    bool holdWakeLock = false,
  }) async {}

  @override
  Future<void> stopForegroundService() async {}

  @override
  Future<void> setKeepScreenOn(bool enabled) async {}

  @override
  Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
  }) async {}
}
