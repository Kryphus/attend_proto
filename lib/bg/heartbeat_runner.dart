import 'dart:async';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/distance.dart';
import 'heartbeat_task.dart';

/// Service runner for managing the background heartbeat task
/// 
/// This class provides methods to start and stop the presence monitoring service
/// that runs location heartbeats every 15 minutes.
class HeartbeatRunner {
  // ⛔️ Remove any cached bools; always ask the plugin.
  static Future<bool> isRunning() async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startPresence({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) async {
    // Save fence data so the handler can read it in the background
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fence_data', '$centerLat,$centerLng,$radiusMeters');

    // Start service
    final isRunning = await FlutterForegroundTask.isRunningService;
    final result = isRunning
        ? await FlutterForegroundTask.restartService()
        : await FlutterForegroundTask.startService(
            serviceId: 256,
            notificationTitle: 'Attendance Tracker',
            notificationText: 'Starting presence monitoring…',
            callback: startCallback, // <- from heartbeat_task.dart
          );

    // Poll briefly to avoid a race where binding isn't done yet
    final ok = await _waitUntilRunning();
    print('DEBUG: Service running: $ok');

    // Make the text flip so you can see minute updates in the tray
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Attendance Tracker',
      notificationText: ok ? 'Monitoring presence…' : 'Failed to start',
    );
  }

  static Future<void> stopPresence() async {
    await FlutterForegroundTask.stopService();
  }

  static Future<bool> _waitUntilRunning({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      if (await FlutterForegroundTask.isRunningService) return true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }
}

