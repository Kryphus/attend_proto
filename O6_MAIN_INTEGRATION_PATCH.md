# O6 - Main.dart Integration Patch

## Overview
This patch integrates the O6 UI widgets into main.dart. Apply these changes carefully.

---

## Change 1: Add Imports (After line 24)

**Location**: `lib/main.dart` line 24 (after `import 'domain/rules/local_rules.dart';`)

**ADD these 3 lines:**
```dart
import 'widgets/offline_banner.dart';
import 'widgets/event_status_card.dart';
import 'widgets/event_history_list.dart';
```

---

## Change 2: Update MyApp Class to Pass Repos

**Location**: Around line 128-137

**FIND:**
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

**REPLACE WITH:**
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

---

## Change 3: Update runApp Call in main()

**Location**: Around line 120-124

**FIND:**
```dart
  runApp(MyApp(
    syncService: syncService,
    attendanceService: attendanceService,
    connectivityService: connectivityService,
  ));
```

**REPLACE WITH:**
```dart
  runApp(MyApp(
    syncService: syncService,
    attendanceService: attendanceService,
    connectivityService: connectivityService,
    database: database,
    eventLogRepo: eventLogRepo,
  ));
```

---

## Change 4: Update MaterialApp home Property

**Location**: Around line 148-152

**FIND:**
```dart
        home: AttendanceHomePage(
          syncService: syncService,
          attendanceService: attendanceService,
          connectivityService: connectivityService,
        ),
```

**REPLACE WITH:**
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

## Change 5: Update AttendanceHomePage Class

**Location**: Around line 171-182

**FIND:**
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

**REPLACE WITH:**
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

---

## Change 6: Add State Variables

**Location**: Around line 203 (after `bool _isEventActive = false;`)

**ADD these lines AFTER the existing state variables:**
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

## Change 7: Add Status Update Methods

**Location**: Around line 244 (after `_addFeatureFlagsToLog()` method)

**ADD these methods:**
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
        title: const Text('Event Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${event.type}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Status: ${event.status}'),
            const SizedBox(height: 8),
            Text('Created: ${event.createdAt}'),
            if (event.serverReason != null) ...[
              const SizedBox(height: 12),
              const Text('Reason:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(event.serverReason!, style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
```

---

## Change 8: Update initState

**Location**: Around line 217-240

**FIND the END of initState (the closing brace):**
```dart
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

**ADD this line BEFORE the closing brace:**
```dart
    // Listen for connectivity changes
    widget.connectivityService.connectivityStream.listen((isConnected) {
      _addTrackingLog('🌐 Connectivity changed: ${isConnected ? "Online" : "Offline"}');
      if (isConnected) {
        _addTrackingLog('🔄 Network regained - sync will resume');
      } else {
        _addTrackingLog('📴 Network lost - working offline');
      }
    });
    
    // O6: Start status updates
    _startStatusUpdates();
  }
```

---

## Change 9: Update dispose Method

**Location**: Around line 408

**FIND:**
```dart
  @override
  void dispose() {
    _heartbeatSimulator?.cancel();
    super.dispose();
  }
```

**REPLACE WITH:**
```dart
  @override
  void dispose() {
    _heartbeatSimulator?.cancel();
    _statusUpdateTimer?.cancel(); // O6: Clean up status timer
    super.dispose();
  }
```

---

## Change 10: Replace _syncNow Method

**Location**: Around line 542-562

**FIND:**
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

**REPLACE WITH:**
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

## Change 11: Update Sync Now Button

**Location**: Around line 738-758

**FIND:**
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

**REPLACE WITH:**
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
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.sync, size: 20),
                      label: Text(
                        _pendingEventCount > 0 
                          ? 'Sync Now ($_pendingEventCount)' 
                          : 'Sync Now',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

## Change 12: Wrap Body in Stack (for Offline Banner)

**Location**: Around line 581-583

**FIND:**
```dart
    backgroundColor: Colors.grey[50],
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
```

**REPLACE WITH:**
```dart
    backgroundColor: Colors.grey[50],
    body: Stack(  // O6: Wrapped in Stack for offline banner
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.only(
            top: widget.connectivityService.isConnected ? 20 : 70,  // Space for banner
            left: 20,
            right: 20,
            bottom: 20,
          ),
```

---

## Change 13: Add Status Card & Event History

**Location**: Around line 894-896 (BEFORE "// Tracking Logs Container")

**FIND:**
```dart
              ],
            ),
            const SizedBox(height: 16),
            
            // Tracking Logs Container (only show when tracking)
```

**ADD BEFORE "// Tracking Logs Container":**
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
```

---

## Change 14: Close Stack & Add Offline Banner

**Location**: Very END of build method (around line 1071)

**FIND:**
```dart
            ],
          ),
        ),
      ),
    );
  }
}
```

**REPLACE WITH:**
```dart
            ],
          ),
        ),
          ),  // O6: Closing SingleChildScrollView
          
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
                  child: const OfflineBanner(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],  // O6: Closing Stack children
      ),  // O6: Closing Stack
    );
  }
}
```

---

## ✅ Verification Steps After Integration

### 1. Check for Syntax Errors
```powershell
flutter analyze lib/main.dart
```

**Expected Output:**
```
Analyzing...
No issues found!
```

### 2. Run the App
```powershell
flutter run
```

**Expected: App compiles and runs successfully**

### 3. Visual Verification Checklist

When app launches:
- [ ] No compile errors
- [ ] Event Status Card visible (shows "0 events" / "Never")
- [ ] Event History shows "No events yet"
- [ ] Sync Now button shows "Sync Now" (no count)

Turn OFF wifi/mobile data:
- [ ] Orange offline banner appears at top
- [ ] Sync Now button becomes gray/disabled
- [ ] Activity log shows "Offline"

Turn ON wifi/mobile data:
- [ ] Orange banner disappears
- [ ] Sync Now button becomes teal/enabled
- [ ] Activity log shows "Online"

After check-in:
- [ ] Pending count changes to "1 event"
- [ ] Sync button shows "Sync Now (1)"
- [ ] Event appears in Event History with yellow PENDING pill

After clicking Sync Now (when online):
- [ ] Button shows spinner
- [ ] Activity log shows "Starting sync..." then "Starting reconciliation..."
- [ ] Pending count goes to 0
- [ ] Event pill turns green (CONFIRMED) or red (REJECTED)
- [ ] Last sync time updates to "Just now"

---

## 🐛 Common Issues & Fixes

### Issue: "Undefined name 'EventLogData'"
**Fix**: Make sure import is: `import 'data/local/db.dart';`

### Issue: "setState() called after dispose"
**Fix**: Ensure `if (mounted)` check is in `_updateEventStatuses()`

### Issue: "The method 'getCountByStatus' isn't defined"
**Fix**: Make sure you're using `widget.eventLogRepo` not just `eventLogRepo`

### Issue: Offline banner not showing
**Fix**: Verify Stack wrapping is correct and StreamBuilder is OUTSIDE SingleScrollView

---

## Summary

**Changes**: 14 sections in `lib/main.dart`
**New Imports**: 3 widget files
**No Supabase/SQL changes needed**: ✅

After applying all changes, the app will have:
- ✅ Offline banner
- ✅ Pending event count
- ✅ Last sync timestamp
- ✅ Event history with status pills
- ✅ Enhanced sync button

