import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/map_fence_page.dart';
import 'services/biometric_service.dart';
import 'services/logging_service.dart';
import 'utils/distance.dart';
import 'bg/heartbeat_runner.dart';
import 'bg/heartbeat_task.dart';
import 'config/feature_flags.dart';
import 'data/local/db.dart';
import 'data/local/event_log_repo.dart';
import 'data/local/outbox_repo.dart';
import 'data/local/sync_cursor_repo.dart';
import 'data/remote/api_client.dart';
import 'sync/sync_service.dart';
import 'sync/connectivity_service.dart';
import 'config/supabase_config.dart';
import 'domain/attendance_service.dart';
import 'domain/heartbeat_service.dart';
import 'domain/rules/local_rules.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize and log feature flags
  await FeatureFlags.initialize();
  print(FeatureFlags.getLogString());

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Initialize database
  final database = AppDatabase();
  final eventLogRepo = EventLogRepo(database);
  final outboxRepo = OutboxRepo(database);
  final syncCursorRepo = SyncCursorRepo(database);

  // Initialize sync services
  final connectivityService = ConnectivityService();
  await connectivityService.initialize(); // Initialize connectivity service
  
  final apiClient = SupabaseConfig.client != null ? ApiClient(SupabaseConfig.client!) : null;
  final syncService = SyncService(
    connectivityService: connectivityService,
    syncCursorRepo: syncCursorRepo,
    apiClient: apiClient,
  );

  // Initialize attendance and heartbeat services
  final biometricService = BiometricService();
  final attendanceService = AttendanceService(
    eventLogRepo: eventLogRepo,
    outboxRepo: outboxRepo,
    biometricService: biometricService,
  );
  final heartbeatService = HeartbeatService(
    eventLogRepo: eventLogRepo,
    outboxRepo: outboxRepo,
  );

  // Initialize sync service (will start background sync)
  try {
    await syncService.initialize();
  } catch (e) {
    logger.error('Failed to initialize sync service', 'main', {'error': e.toString()});
  }

  // Log initialization
  logger.info(
    'App initialization complete',
    'main',
    {
      'environment': FeatureFlags.environment,
      'heartbeat_interval_ms': FeatureFlags.heartbeatInterval.inMilliseconds,
      'sync_interval_ms': FeatureFlags.syncInterval.inMilliseconds,
      'sync_service_initialized': syncService.isInitialized,
      'supabase_configured': SupabaseConfig.isConfigured,
      'api_client_available': apiClient != null,
    },
  );

  // UI <-> Task comms
  FlutterForegroundTask.initCommunicationPort();

  // Android 13+: ask for notification permission
  final perm = await FlutterForegroundTask.checkNotificationPermission();
  if (perm != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }

  // Foreground task + channel config
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'attendance_channel',
      channelName: 'Attendance',
      channelDescription: 'Presence monitoring',
      channelImportance: NotificationChannelImportance.HIGH, // 👈 visible updates
      priority: NotificationPriority.HIGH,
      onlyAlertOnce: false, // 👈 allow alert on each update
      showWhen: true,
    ),
    iosNotificationOptions: IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // Use repeat event based on feature flags
      eventAction: ForegroundTaskEventAction.repeat(
        FeatureFlags.heartbeatInterval.inMilliseconds,
      ),
      allowWakeLock: true,  // 👈 keep CPU on during doze
      allowWifiLock: true,
      autoRunOnBoot: false,
    ),
  );

  runApp(MyApp(
    syncService: syncService,
    attendanceService: attendanceService,
    connectivityService: connectivityService,
  ));
}

class MyApp extends StatelessWidget {
  final SyncService syncService;
  final AttendanceService attendanceService;
  final ConnectivityService connectivityService;

  const MyApp({
    super.key, 
    required this.syncService,
    required this.attendanceService,
    required this.connectivityService,
  });

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Attendance Tracker',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: AttendanceHomePage(
          syncService: syncService,
          attendanceService: attendanceService,
          connectivityService: connectivityService,
        ),
      ),
    );
  }
}

class AttendanceHomePage extends StatefulWidget {
  final SyncService syncService;
  final AttendanceService attendanceService;
  final ConnectivityService connectivityService;

  const AttendanceHomePage({
    super.key, 
    required this.syncService,
    required this.attendanceService,
    required this.connectivityService,
  });

  @override
  State<AttendanceHomePage> createState() => _AttendanceHomePageState();
}

class _AttendanceHomePageState extends State<AttendanceHomePage> {
  double? _geofenceLatitude;
  double? _geofenceLongitude;
  double? _geofenceRadius;
  bool _isPresenceTracking = false;
  String _presenceStatus = 'Not tracking';
  List<String> _trackingLogs = [];
  Timer? _heartbeatSimulator;
  
  // Event duration variables
  DateTime? _eventStartTime;
  DateTime? _eventEndTime;
  DateTime? _checkInTime;
  bool _isEventActive = false;

  @override
  void initState() {
    super.initState();
    // Set up logging callback to integrate with existing UI logs
    logger.setUILogCallback(_addTrackingLog);

    // Log database initialization
    _addTrackingLog('💾 Local database initialized');
    _addFeatureFlagsToLog();

    // Log sync service status
    _addTrackingLog('🔄 Sync service: ${widget.syncService.isInitialized ? "Ready" : "Initializing"}');
    
    // Log initial connectivity status
    _addTrackingLog('🌐 Connectivity: ${widget.connectivityService.isConnected ? "Online" : "Offline"}');
    
    // Listen for connectivity changes
    widget.connectivityService.connectivityStream.listen((isConnected) {
      _addTrackingLog('🌐 Connectivity changed: ${isConnected ? "Online" : "Offline"}');
      if (isConnected) {
        _addTrackingLog('🔄 Network regained - sync will resume');
      } else {
        _addTrackingLog('📴 Network lost - working offline');
      }
    });
  }

  void _addTrackingLog(String message) {
    setState(() {
      _trackingLogs.insert(0, '${DateTime.now().toString().substring(11, 19)} - $message');
      // Keep only last 10 logs to avoid UI clutter
      if (_trackingLogs.length > 10) {
        _trackingLogs = _trackingLogs.take(10).toList();
      }
    });
  }

  void _addFeatureFlagsToLog() {
    _addTrackingLog('🚩 Environment: ${FeatureFlags.environment}');
    _addTrackingLog('⏱️ Heartbeat: ${FeatureFlags.heartbeatInterval}');
    _addTrackingLog('🔄 Sync: ${FeatureFlags.syncInterval}');
  }

  void _startHeartbeatSimulator() {
    _heartbeatSimulator?.cancel();
    _heartbeatSimulator = Timer.periodic(FeatureFlags.heartbeatInterval, (timer) {
      if (_isPresenceTracking) {
        // Simulate different messages based on random chance
        final random = Random();
        final messages = [
          '🎯 You\'re still inside the fence! Keep up the great work!',
          '✅ Location confirmed - you\'re in the right place!',
          '📍 Still tracking your presence - all good!',
          '🎉 Another minute of successful attendance!',
          '💪 You\'re doing great - stay in the zone!',
        ];
        
        final selectedMessage = messages[random.nextInt(messages.length)];
        _addTrackingLog(selectedMessage);
        
        // Add coordinates info occasionally
        if (random.nextBool()) {
          _addTrackingLog('📍 Current position: (${_geofenceLatitude!.toStringAsFixed(6)}, ${_geofenceLongitude!.toStringAsFixed(6)})');
        }
      }
    });
  }

  void _stopHeartbeatSimulator() {
    _heartbeatSimulator?.cancel();
    _heartbeatSimulator = null;
  }

  void _setEventDuration() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Set default start time to current time
    final defaultStartTime = now;
    // Set default end time to 4:30 PM today
    final defaultEndTime = today.add(const Duration(hours: 16, minutes: 30));
    
    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(defaultStartTime),
    );
    
    if (startTime != null) {
      final endTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(defaultEndTime),
      );
      
      if (endTime != null) {
        setState(() {
          _eventStartTime = today.add(Duration(hours: startTime.hour, minutes: startTime.minute));
          
          // Calculate end time - if it's before start time, assume it's next day
          var calculatedEndTime = today.add(Duration(hours: endTime.hour, minutes: endTime.minute));
          if (calculatedEndTime.isBefore(_eventStartTime!)) {
            calculatedEndTime = calculatedEndTime.add(const Duration(days: 1));
          }
          _eventEndTime = calculatedEndTime;
          _isEventActive = true;
        });
        
        _addTrackingLog('📅 Event scheduled: ${_formatTime(_eventStartTime!)} - ${_formatTime(_eventEndTime!)}');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Event scheduled from ${_formatTime(_eventStartTime!)} to ${_formatTime(_eventEndTime!)}'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _checkOut() async {
    if (_checkInTime == null) return;
    
    final now = DateTime.now();
    final duration = now.difference(_checkInTime!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    _addTrackingLog('🏁 Checked out successfully!');
    _addTrackingLog('⏱️ Total attendance: ${hours}h ${minutes}m');
    
    setState(() {
      _isPresenceTracking = false;
      _presenceStatus = 'Checked out';
      _checkInTime = null;
      _isEventActive = false;
    });
    
    _stopHeartbeatSimulator();
    await HeartbeatRunner.stopPresence();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Checked out! Total attendance: ${hours}h ${minutes}m'),
        backgroundColor: Colors.green,
      ),
    );
  }

  bool _canCheckIn() {
    if (!_isEventActive || _eventStartTime == null || _eventEndTime == null) return false;
    final now = DateTime.now();
    return now.isAfter(_eventStartTime!) && now.isBefore(_eventEndTime!);
  }

  bool _shouldCheckOut() {
    if (_eventEndTime == null) return false;
    return DateTime.now().isAfter(_eventEndTime!);
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _heartbeatSimulator?.cancel();
    super.dispose();
  }

  void _setGeofence() async {
    // Navigate to map screen to set geofence
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapFencePage(),
      ),
    );

    // Handle the returned fence data
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _geofenceLatitude = result['centerLat'] as double;
        _geofenceLongitude = result['centerLng'] as double;
        _geofenceRadius = result['radius'] as double;
      });
      
      _addTrackingLog('🎯 Geofence updated: (${_geofenceLatitude!.toStringAsFixed(6)}, ${_geofenceLongitude!.toStringAsFixed(6)}) with ${_geofenceRadius!.round()}m radius');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geofence set successfully!')),
      );
    }
  }

  void _checkIn() async {
    try {
      // 1. Check if geofence is set
      if (_geofenceLatitude == null || _geofenceLongitude == null || _geofenceRadius == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please set geofence first'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      _addTrackingLog('🚀 Starting check-in process...');
      _addTrackingLog('🌐 Connectivity: ${widget.connectivityService.isConnected ? "Online" : "Offline"}');

      // 2. Create session and device info for validation
      final session = SessionInfo(
        sessionId: 'session-${DateTime.now().millisecondsSinceEpoch}',
        startTime: DateTime.now().subtract(const Duration(hours: 1)), // Allow 1 hour before
        endTime: DateTime.now().add(const Duration(hours: 8)), // Allow 8 hours after
        centerLat: _geofenceLatitude!,
        centerLng: _geofenceLongitude!,
        radiusMeters: _geofenceRadius!,
      );

      final device = DeviceInfo(
        deviceId: 'device-${DateTime.now().millisecondsSinceEpoch}',
        isTrusted: true, // For demo purposes
      );

      // 3. Use AttendanceService to capture sign-in (includes all validation)
      final result = await widget.attendanceService.captureSignIn(
        session: session,
        device: device,
        lastEventType: null, // First event
      );

      if (result.success) {
        // 4. On success → start background tracking
        _addTrackingLog('✅ Sign-in captured successfully!');
        _addTrackingLog('📝 Event ID: ${result.eventId}');
        _addTrackingLog('💾 Status: PENDING (will sync when online)');
        
        await HeartbeatRunner.startPresence(
          centerLat: _geofenceLatitude!,
          centerLng: _geofenceLongitude!,
          radiusMeters: _geofenceRadius!,
        );

        setState(() {
          _isPresenceTracking = true;
          _presenceStatus = 'Tracking started - Inside fence';
          _checkInTime = DateTime.now();
        });
        
        _addTrackingLog('🕐 Check-in time: ${_formatTime(_checkInTime!)}');
        _startHeartbeatSimulator();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.connectivityService.isConnected 
              ? 'Check-in successful - will sync to server'
              : 'Check-in successful - saved offline (will sync when online)'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Handle failure
        _addTrackingLog('❌ Sign-in failed: ${result.errorMessage}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Check-in failed: ${result.errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }

    } catch (e) {
      _addTrackingLog('💥 Check-in error: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Check-in failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _stopPresence() async {
    try {
      _addTrackingLog('🛑 Stopping presence monitoring...');
      await HeartbeatRunner.stopPresence();
      
      _stopHeartbeatSimulator();
      
      setState(() {
        _isPresenceTracking = false;
        _presenceStatus = 'Not tracking';
        _trackingLogs.clear(); // Clear logs when stopping
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Presence tracking stopped'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to stop tracking: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _syncNow() async {
    try {
      _addTrackingLog('🔄 Manual sync triggered...');
      await widget.syncService.syncNow();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync triggered - check logs for progress'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      _addTrackingLog('❌ Sync failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TagMeIn+',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome to TagMeIn+',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Smart attendance tracking with geofencing',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Action Buttons Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Set Event Duration Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _setEventDuration,
                      icon: const Icon(Icons.schedule, size: 20),
                      label: const Text(
                        'Set Event Duration',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Set Geofence Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _setGeofence,
                      icon: const Icon(Icons.location_on, size: 20),
                      label: const Text(
                        'Set Geofence',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Check In Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _canCheckIn() ? _checkIn : null,
                      icon: const Icon(Icons.check_circle, size: 20),
                      label: Text(
                        _canCheckIn() ? 'Check In' : 'Event Not Active',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _canCheckIn() ? Colors.purple[600] : Colors.grey[400],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  
                  // Check Out Button (only show when tracking and event should end)
                  if (_isPresenceTracking && _shouldCheckOut()) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _checkOut,
                        icon: const Icon(Icons.logout, size: 20),
                        label: const Text(
                          'Check Out',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[600],
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                  
                  // Sync Now Button (always available)
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _syncNow,
                      icon: const Icon(Icons.sync, size: 20),
                      label: const Text(
                        'Sync Now',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[600],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  
                  // Stop Tracking Button (only show when tracking and not at end time)
                  if (_isPresenceTracking && !_shouldCheckOut()) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _stopPresence,
                        icon: const Icon(Icons.stop, size: 20),
                        label: const Text(
                          'Stop Tracking',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[600],
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Status Cards Section
            Row(
              children: [
                // Presence Status Card
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isPresenceTracking ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: _isPresenceTracking ? Colors.green[600] : Colors.grey[400],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Status',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _presenceStatus,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _isPresenceTracking ? Colors.green[600] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Event Duration Card
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              color: _isEventActive ? Colors.blue[600] : Colors.grey[400],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Event',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isEventActive 
                              ? '${_formatTime(_eventStartTime!)} - ${_formatTime(_eventEndTime!)}'
                              : 'Not Set',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _isEventActive ? Colors.blue[600] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Tracking Logs Container (only show when tracking)
            if (_isPresenceTracking) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.analytics,
                          color: Colors.purple[600],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Activity Log',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_trackingLogs.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_empty, color: Colors.grey[400], size: 20),
                            const SizedBox(width: 12),
                            Text(
                              'Waiting for tracking updates...',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _trackingLogs.length,
                          itemBuilder: (context, index) {
                            final log = _trackingLogs[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Geofence Information Display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: _geofenceLatitude != null ? Colors.green[600] : Colors.grey[400],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Geofence Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_geofenceLatitude != null && _geofenceLongitude != null && _geofenceRadius != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow('Center', '${_geofenceLatitude!.toStringAsFixed(6)}, ${_geofenceLongitude!.toStringAsFixed(6)}'),
                          const SizedBox(height: 8),
                          _buildInfoRow('Radius', '${_geofenceRadius!.toStringAsFixed(1)} meters'),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.grey[400], size: 20),
                          const SizedBox(width: 12),
            Text(
                            'No geofence set',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}