# O6 - UI Integration Guide

## ✅ Step 1: Import New Widgets (lib/main.dart)

**Action**: Add these imports after the existing imports (around line 24):

```dart
import 'widgets/offline_banner.dart';
import 'widgets/event_status_card.dart';
import 'widgets/event_history_list.dart';
```

**Location**: After `import 'domain/rules/local_rules.dart';`

---

## ✅ Step 2: Pass Database & Repos to HomePage

**Action**: Update `AttendanceHomePage` class to accept repos:

### 2a. Update AttendanceHomePage constructor (around line 171):

**Find:**
```dart
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
```

**Replace with:**
```dart
class AttendanceHomePage extends StatefulWidget {
  final SyncService syncService;
  final AttendanceService attendanceService;
  final ConnectivityService connectivityService;
  final AppDatabase database;
  final EventLogRepo eventLogRepo;

  const AttendanceHomePage({
    super.key, 
    required this.syncService,
    required this.attendanceService,
    required this.connectivityService,
    required this.database,
    required this.eventLogRepo,
  });
```

### 2b. Update main() to pass repos (around line 120):

**Find:**
```dart
runApp(MyApp(
  syncService: syncService,
  attendanceService: attendanceService,
  connectivityService: connectivityService,
));
```

**Replace with:**
```dart
runApp(MyApp(
  syncService: syncService,
  attendanceService: attendanceService,
  connectivityService: connectivityService,
  database: database,
  eventLogRepo: eventLogRepo,
));
```

### 2c. Update MyApp class (around line 128):

**Find:**
```dart
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
```

**Replace with:**
```dart
class MyApp extends StatelessWidget {
  final SyncService syncService;
  final AttendanceService attendanceService;
  final ConnectivityService connectivityService;
  final AppDatabase database;
  final EventLogRepo eventLogRepo;

  const MyApp({
    super.key, 
    required this.syncService,
    required this.attendanceService,
    required this.connectivityService,
    required this.database,
    required this.eventLogRepo,
  });
```

### 2d. Update MaterialApp home (around line 148):

**Find:**
```dart
home: AttendanceHomePage(
  syncService: syncService,
  attendanceService: attendanceService,
  connectivityService: connectivityService,
),
```

**Replace with:**
```dart
home: AttendanceHomePage(
  syncService: syncService,
  attendanceService: attendanceService,
  connectivityService: connectivityService,
  database: database,
  eventLogRepo: eventLogRepo,
),
```

---

## ✅ Step 3: Add State Variables (_AttendanceHomePageState)

**Action**: Add new state variables after existing ones (around line 203):

**Find:**
```dart
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
```

**Add after the above (before @override void initState):**
```dart
  
  // O6: UI indicator state
  int _pendingEventCount = 0;
  DateTime? _lastSyncTime;
  DateTime? _lastReconcileTime;
  List<EventLogData> _recentEvents = [];
  Timer? _statusUpdateTimer;
  bool _isSyncing = false;
```

---

## ✅ Step 4: Add Status Update Methods

**Action**: Add these methods after `_addFeatureFlagsToLog()` (around line 244):

```dart
  /// O6: Start periodic status updates
  void _startStatusUpdates() {
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _updateEventStatuses();
    });
    _updateEventStatuses(); // Initial update
  }

  /// O6: Update event statuses from database
  Future<void> _updateEventStatuses() async {
    try {
      final pendingCount = await widget.eventLogRepo.getCountByStatus(EventStatus.pending);
      final recentEvents = await widget.eventLogRepo.getEvents(limit: 20);
      final syncStatus = await widget.syncService.getSyncStatus();
      final lastReconcile = await widget.syncService.getLastReconcileTime();
      
      if (mounted) {
        setState(() {
          _pendingEventCount = pendingCount;
          _recentEvents = recentEvents;
          _lastSyncTime = syncStatus.lastSyncTime;
          _lastReconcileTime = lastReconcile;
        });
      }
    } catch (e) {
      // Silently handle errors to avoid disrupting UI
      print('Error updating status: $e');
    }
  }

  /// O6: Show event details dialog
  void _showEventDetails(EventLogData event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Event Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${event.type}', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('Status: ${event.status}'),
            SizedBox(height: 8),
            Text('Created: ${event.createdAt}'),
            if (event.serverReason != null) ...[
              SizedBox(height: 12),
              Text('Reason:', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 4),
              Text(event.serverReason!, style: TextStyle(fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
```

---

## ✅ Step 5: Update initState

**Action**: Add status updates initialization in `initState()` (around line 227):

**Find:**
```dart
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
```

**Add this line at the END of initState (before the closing brace):**
```dart
    
    // O6: Start status updates
    _startStatusUpdates();
  }
```

---

## ✅ Step 6: Update dispose

**Action**: Add timer cleanup in `dispose()` (around line 408):

**Find:**
```dart
  @override
  void dispose() {
    _heartbeatSimulator?.cancel();
    super.dispose();
  }
```

**Replace with:**
```dart
  @override
  void dispose() {
    _heartbeatSimulator?.cancel();
    _statusUpdateTimer?.cancel(); // O6: Clean up status timer
    super.dispose();
  }
```

---

## ✅ Step 7: Enhanced Sync Now Method

**Action**: Replace the existing `_syncNow()` method (around line 542):

**Find:**
```dart
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
```

**Replace with:**
```dart
  void _syncNow() async {
    // Check if offline
    if (!widget.connectivityService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot sync - you are offline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);
    
    try {
      _addTrackingLog('🔄 Manual sync triggered...');
      await widget.syncService.syncNow();
      
      _addTrackingLog('🔄 Starting reconciliation...');
      await widget.syncService.reconcileNow();
      
      _addTrackingLog('✅ Sync completed!');
      
      // Refresh statuses immediately
      await _updateEventStatuses();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync completed successfully'),
          backgroundColor: Colors.green,
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
    } finally {
      setState(() => _isSyncing = false);
    }
  }
```

---

## ✅ Step 8: Update Sync Now Button

**Action**: Update the Sync Now button to show loading state (around line 740):

**Find:**
```dart
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
```

**Replace with:**
```dart
// Sync Now Button (always available)
const SizedBox(height: 12),
SizedBox(
  width: double.infinity,
  height: 56,
  child: ElevatedButton.icon(
    onPressed: _isSyncing || !widget.connectivityService.isConnected 
      ? null 
      : _syncNow,
    icon: _isSyncing
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Icon(Icons.sync, size: 20),
    label: Text(
      _pendingEventCount > 0 
        ? 'Sync Now ($_pendingEventCount)' 
        : 'Sync Now',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: _isSyncing || !widget.connectivityService.isConnected
        ? Colors.grey[400]
        : Colors.teal[600],
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  ),
),
```

---

## ✅ Step 9: Add Offline Banner to UI

**Action**: Wrap the entire body in a Stack and add offline banner (around line 581):

**Find:**
```dart
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
```

**Replace with:**
```dart
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
    body: Stack(  // CHANGED: Wrapped in Stack
      children: [
        // Main content
        SingleChildScrollView(
          padding: EdgeInsets.only(
            top: widget.connectivityService.isConnected ? 20 : 70,  // CHANGED: Space for banner
            left: 20,
            right: 20,
            bottom: 20,
          ),
          child: Column(
```

---

## ✅ Step 10: Add Status Card & Event History (continued from Step 9)

**Action**: After the existing status cards (around line 894), add the new widgets:

**Find** (around line 894):
```dart
            ],
          ),
          const SizedBox(height: 16),
          
          // Tracking Logs Container (only show when tracking)
          if (_isPresenceTracking) ...[
```

**Add BEFORE `// Tracking Logs Container`:**
```dart
            ],
          ),
          const SizedBox(height: 16),
          
          // O6: Event Status Card (Pending count + Last sync)
          EventStatusCard(
            pendingCount: _pendingEventCount,
            lastSyncTime: _lastSyncTime,
            lastReconcileTime: _lastReconcileTime,
          ),
          const SizedBox(height: 16),
          
          // O6: Event History List
          EventHistoryList(
            events: _recentEvents,
            onEventTap: _showEventDetails,
          ),
          const SizedBox(height: 16),
          
          // Tracking Logs Container (only show when tracking)
          if (_isPresenceTracking) ...[
```

---

## ✅ Step 11: Close the Stack (at the END of build method)

**Action**: At the very END of the build method, close the Stack:

**Find** (around line 1071, end of build method):
```dart
            ],
          ),
        ),
      ),
    );
  }
}
```

**Replace with:**
```dart
            ],
          ),
        ),
      ),  // CHANGED: Closing SingleChildScrollView
        
        // O6: Offline banner overlay
        StreamBuilder<bool>(
          stream: widget.connectivityService.connectivityStream,
          initialData: widget.connectivityService.isConnected,
          builder: (context, snapshot) {
            if (snapshot.data == false) {
              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: OfflineBanner(),
              );
            }
            return SizedBox.shrink();
          },
        ),
      ],  // CHANGED: Closing Stack children
    ),  // CHANGED: Closing Stack
  );
}
}
```

---

## ✅ Testing After Integration

### Run the app:
```powershell
flutter run
```

### Expected Behavior:
1. ✅ **Offline Banner**: Appears at top when you disconnect wifi/mobile data
2. ✅ **Event Status Card**: Shows "0 events" initially, "Never" for last sync
3. ✅ **Sync Now Button**: 
   - Shows pending count if > 0
   - Disabled (gray) when offline
   - Shows spinner while syncing
4. ✅ **Event History**: Shows "No events yet" initially
5. ✅ After check-in: 
   - Pending count increases to 1
   - Event appears in history with yellow PENDING pill
6. ✅ After sync (when online):
   - Pending count goes to 0
   - Event pill turns green (CONFIRMED) or red (REJECTED)
   - Last sync time updates

---

## 🐛 Troubleshooting

### Error: "Null check operator used on a null value"
**Fix**: Make sure you passed `database` and `eventLogRepo` to `AttendanceHomePage`

### Error: "The method 'getCountByStatus' isn't defined"
**Fix**: Make sure you're using the correct import: `import 'data/local/event_log_repo.dart';`

### Error: "setState() called after dispose()"
**Fix**: Check that `if (mounted)` is used in `_updateEventStatuses()`

### Banner not showing when offline
**Fix**: Verify `StreamBuilder` is outside the `SingleChildScrollView` and inside the `Stack`

---

## ✅ Verification Checklist

After integration, verify:
- [ ] App compiles without errors
- [ ] Offline banner shows/hides based on connectivity
- [ ] Pending count displays correctly
- [ ] Last sync time updates after manual sync
- [ ] Event history shows recent events
- [ ] Status pills have correct colors
- [ ] Tapping event shows details dialog
- [ ] Sync button disables when offline
- [ ] Sync button shows spinner during sync

---

## 📝 Summary of Changes

**Files Modified**: 1
- `lib/main.dart` (12 sections updated)

**Files Created**: 4
- `lib/widgets/offline_banner.dart`
- `lib/widgets/status_pill.dart`
- `lib/widgets/event_status_card.dart`
- `lib/widgets/event_history_list.dart`

**No Supabase/SQL changes needed** ✅

