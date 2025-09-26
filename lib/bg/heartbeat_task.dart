import 'dart:async';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/distance.dart';

/// Background task handler for presence monitoring
/// 
/// This class implements the TaskHandler interface to provide
/// location-based heartbeat monitoring in the background.
class HeartbeatTaskHandler extends TaskHandler {
  Timer? _timer;
  String? _fenceData;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _fenceData = prefs.getString('fence_data');
      print('DEBUG: HeartbeatTaskHandler.onStart called');
      print('DEBUG: Loaded fence data: $_fenceData');
    } catch (e) {
      print('DEBUG: onStart error: $e');
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Attendance Tracker',
        notificationText: 'Start error: $e',
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // This method is called every 1 minute by the foreground task
    print('DEBUG: onRepeatEvent called at $timestamp');
    _performHeartbeat();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
  }

  @override
  void onEvent(DateTime timestamp, SendPort? sendPort) {
    // Handle any events if needed
  }

  @override
  void onButtonPressed(String id) {
    // Handle notification button presses if needed
  }

  Future<void> _performHeartbeat() async {
    try {
      // If no fence data yet, surface that in the notif so you can see the tick
      if (_fenceData == null) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Attendance Tracker',
          notificationText: 'No fence set',
        );
        return;
      }

      // Check location permission; still update notif so tick is visible
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Attendance Tracker',
          notificationText: 'Location permission not granted',
        );
        return;
      }

      // Get position & compute distance
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final parts = _fenceData!.split(',');
      final centerLat = double.parse(parts[0]);
      final centerLng = double.parse(parts[1]);
      final radius = double.parse(parts[2]);

       final meters = Geolocator.distanceBetween(
         pos.latitude, pos.longitude, centerLat, centerLng,
       );
      final inside = meters <= radius;

      await FlutterForegroundTask.updateService(
        notificationTitle: 'Attendance Tracker',
        notificationText: inside
            ? 'Inside fence (${meters.round()} m)'
            : 'Outside fence (${meters.round()} m)',
      );
    } catch (e) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Attendance Tracker',
        notificationText: 'Heartbeat error: $e',
      );
    }
  }
}


/// Entry point for the background task
/// 
/// This function is called by flutter_foreground_task to start the background service.
/// It sets up the task handler and starts the service.
@pragma('vm:entry-point')
void startCallback() {
  print('DEBUG: startCallback called');
  try {
    FlutterForegroundTask.setTaskHandler(HeartbeatTaskHandler());
    print('DEBUG: TaskHandler set successfully in startCallback');
  } catch (e) {
    print('DEBUG: Error setting TaskHandler in startCallback: $e');
  }
}
