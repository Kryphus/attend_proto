# O6 - UI Indicators Review & Implementation Plan

## 📋 Existing UI Elements (What's Already There)

### ✅ Already Implemented:
1. **"Sync Now" Button** (Line 738-757)
   - ✅ Exists in Action Buttons section
   - ✅ Calls `_syncNow()` which triggers `widget.syncService.syncNow()`
   - ✅ Shows snackbar feedback
   - ✅ Logs to activity log
   - ⚠️ **Missing**: Loading state, disabled when offline, reconciliation trigger

2. **Connectivity Status in Logs** (Lines 215-226)
   - ✅ Shows "Online" or "Offline" in activity log
   - ✅ Listens to `connectivityService.connectivityStream`
   - ✅ Logs when connectivity changes
   - ⚠️ **Missing**: Visual banner at top of screen

3. **Activity Log Container** (Lines 898-987)
   - ✅ Shows last 10 tracking logs with timestamps
   - ✅ Integrated with `LoggingService` via callback
   - ✅ Already shows connectivity changes, check-ins, sync status
   - ⚠️ **Missing**: Event status pills (PENDING/CONFIRMED/REJECTED)

4. **Status Cards** (Lines 789-894)
   - ✅ Shows presence tracking status
   - ✅ Shows event duration (start-end time)
   - ⚠️ **Missing**: Pending event count, last sync time

---

## 🎯 What Needs to Be Added (O6 Tasks)

### **O6.1 - Offline Banner** 🔴
**Location**: Add at top of Scaffold body (before existing content)

**Requirements**:
- Prominent banner that appears when `connectivityService.isConnected == false`
- Dismissible but reappears on next offline event
- Material Banner or custom Container
- Shows: "📴 Offline Mode - Events will sync when online"

**Implementation**:
```dart
// Wrap body with Stack and add banner as overlay
Stack(
  children: [
    // Existing SingleChildScrollView content
    // ...
    
    // Offline banner (positioned at top)
    if (!connectivityService.isConnected)
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: OfflineBanner(),
      ),
  ],
)
```

---

### **O6.2 - Enhanced Status Indicators** 📊

#### A. **Pending Events Count Chip**
**Location**: Add to Status Cards section (next to existing cards)

**Requirements**:
- Shows count of events with status="PENDING"
- Yellow/amber badge with number
- Queries `EventLogRepo.getCountByStatus(EventStatus.pending)`
- Updates in real-time when events are created/synced

**Design**:
```
┌─────────────────────┐
│ ⏳ Pending Events  │
│     5 events        │  ← Yellow/amber card
└─────────────────────┘
```

#### B. **Last Sync Timestamp**
**Location**: Add to Status Cards section or create new info row

**Requirements**:
- Shows "Last sync: 2m ago" or "Never synced"
- Queries `syncService.getSyncStatus()`
- Updates after each sync
- Includes both data sync AND reconciliation time

**Design**:
```
┌─────────────────────┐
│ 🔄 Last Sync       │
│   2 minutes ago     │  ← Teal/blue card
└─────────────────────┘
```

#### C. **Event Status Pills with Details View**
**Location**: New expandable section below Activity Log

**Requirements**:
- Shows list of all captured events from `EventLogRepo.getEvents()`
- Each event shows:
  - Event type icon (sign-in, sign-out, heartbeat)
  - Timestamp
  - Status pill with color:
    - 🟡 PENDING (yellow) - "Waiting to sync"
    - 🟢 CONFIRMED (green) - "Server validated"
    - 🔴 REJECTED (red) - "Failed validation"
  - Tap pill to see `server_reason` in tooltip/dialog
- Sorted by `created_at` DESC (newest first)
- Limit to last 20 events for performance

**Design**:
```
┌─────────────────────────────────────┐
│ 📝 Event History                    │
├─────────────────────────────────────┤
│ ↓ 14:23  Sign In    [🟡 PENDING]   │
│ ↓ 14:15  Heartbeat  [🟢 CONFIRMED] │
│ ↓ 14:10  Heartbeat  [🔴 REJECTED]  │ ← Tap for reason
│ ↓ 14:05  Heartbeat  [🟢 CONFIRMED] │
│   ...                                │
└─────────────────────────────────────┘
```

---

### **O6.3 - Enhanced "Sync Now" Button** 🔄

**Location**: Existing button at line 738-757

**Requirements**:
- ✅ Already calls `syncService.syncNow()`
- ❌ **Add**: Call `syncService.reconcileNow()` after sync
- ❌ **Add**: Loading spinner while syncing
- ❌ **Add**: Disable when offline
- ❌ **Add**: Show pending count on button (e.g., "Sync Now (5)")
- ❌ **Add**: Better success/error feedback

**Enhanced Implementation**:
```dart
bool _isSyncing = false;
int _pendingCount = 0;

// In initState - listen for pending count updates
// Update _pendingCount whenever events are created

Future<void> _syncNow() async {
  if (!widget.connectivityService.isConnected) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cannot sync - you are offline')),
    );
    return;
  }

  setState(() => _isSyncing = true);
  
  try {
    _addTrackingLog('🔄 Starting sync...');
    await widget.syncService.syncNow();
    
    _addTrackingLog('🔄 Starting reconciliation...');
    await widget.syncService.reconcileNow();
    
    _addTrackingLog('✅ Sync completed!');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
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

// Button widget
ElevatedButton.icon(
  onPressed: _isSyncing || !widget.connectivityService.isConnected 
    ? null 
    : _syncNow,
  icon: _isSyncing 
    ? SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
    : Icon(Icons.sync),
  label: Text(_pendingCount > 0 
    ? 'Sync Now ($_pendingCount)'
    : 'Sync Now'
  ),
  // ... styling
)
```

---

### **O6.4 - Widget Tests** 🧪

**Files to Create**:
1. `test/widgets/offline_banner_test.dart`
2. `test/widgets/event_status_list_test.dart`
3. `test/widgets/sync_button_test.dart`

**Test Scenarios**:
1. ✅ Offline banner appears when connectivity = false
2. ✅ Offline banner disappears when connectivity = true
3. ✅ Pending count updates when events created
4. ✅ Pending count decreases after successful sync
5. ✅ Sync button disabled when offline
6. ✅ Sync button shows loading spinner during sync
7. ✅ Event status pills show correct colors
8. ✅ Tapping rejected event shows reason dialog
9. ✅ Last sync time updates after sync

---

## 📦 New Widgets to Create

### 1. **OfflineBanner** (lib/widgets/offline_banner.dart)
```dart
class OfflineBanner extends StatelessWidget {
  final bool isOffline;
  final VoidCallback? onDismiss;
  
  // Shows banner when isOffline=true
  // Dismissible but reappears on connectivity change
}
```

### 2. **EventStatusCard** (lib/widgets/event_status_card.dart)
```dart
class EventStatusCard extends StatelessWidget {
  final int pendingCount;
  final DateTime? lastSyncTime;
  
  // Shows pending count and last sync in card format
}
```

### 3. **EventHistoryList** (lib/widgets/event_history_list.dart)
```dart
class EventHistoryList extends StatelessWidget {
  final List<EventLogData> events;
  final Function(EventLogData) onEventTap;
  
  // Shows list of events with status pills
  // Tappable to see reason
}
```

### 4. **StatusPill** (lib/widgets/status_pill.dart)
```dart
class StatusPill extends StatelessWidget {
  final EventStatus status;
  final String? reason;
  
  // Color-coded pill: yellow/green/red
  // Shows tooltip on hover/tap
}
```

---

## 🔄 State Management Updates

### Add to `_AttendanceHomePageState`:
```dart
// New state variables
int _pendingEventCount = 0;
DateTime? _lastSyncTime;
DateTime? _lastReconcileTime;
List<EventLogData> _recentEvents = [];
Timer? _statusUpdateTimer;

@override
void initState() {
  super.initState();
  // ... existing code
  
  // Start periodic status updates (every 5 seconds)
  _startStatusUpdates();
}

void _startStatusUpdates() {
  _statusUpdateTimer = Timer.periodic(Duration(seconds: 5), (_) {
    _updateEventStatuses();
  });
}

Future<void> _updateEventStatuses() async {
  final pendingCount = await eventLogRepo.getCountByStatus(EventStatus.pending);
  final recentEvents = await eventLogRepo.getEvents(limit: 20);
  final syncStatus = await syncService.getSyncStatus();
  final lastReconcile = await syncService.getLastReconcileTime();
  
  setState(() {
    _pendingEventCount = pendingCount;
    _recentEvents = recentEvents;
    _lastSyncTime = syncStatus.lastSyncTime;
    _lastReconcileTime = lastReconcile;
  });
}

@override
void dispose() {
  _statusUpdateTimer?.cancel();
  // ... existing dispose code
}
```

---

## 🎨 UI Layout Changes

### Updated Scaffold Structure:
```dart
Scaffold(
  appBar: AppBar(...),
  body: Stack(  // NEW: Wrap in Stack for banner
    children: [
      // Main content (existing SingleChildScrollView)
      SingleChildScrollView(
        padding: EdgeInsets.only(
          top: connectivityService.isConnected ? 20 : 70,  // Space for banner
          left: 20,
          right: 20,
          bottom: 20,
        ),
        child: Column(
          children: [
            // Welcome Section (existing)
            
            // Action Buttons Section (existing - update Sync button)
            
            // NEW: Status Indicators Row
            Row(
              children: [
                // Existing status cards
                // NEW: Pending count card
                // NEW: Last sync card
              ],
            ),
            
            // Activity Log (existing)
            
            // NEW: Event History with Status Pills
            EventHistoryList(
              events: _recentEvents,
              onEventTap: _showEventDetails,
            ),
            
            // Geofence Details (existing)
          ],
        ),
      ),
      
      // NEW: Offline banner overlay
      StreamBuilder<bool>(
        stream: connectivityService.connectivityStream,
        initialData: connectivityService.isConnected,
        builder: (context, snapshot) {
          if (snapshot.data == false) {
            return OfflineBanner();
          }
          return SizedBox.shrink();
        },
      ),
    ],
  ),
)
```

---

## ✅ Implementation Checklist

### Phase 1: Core Indicators (Most Important)
- [ ] Add offline banner at top (O6.1)
- [ ] Add pending count card to status section (O6.2.A)
- [ ] Update "Sync Now" button with loading state & offline disable (O6.3)
- [ ] Add last sync timestamp display (O6.2.B)

### Phase 2: Event Details
- [ ] Create EventHistoryList widget (O6.2.C)
- [ ] Create StatusPill widget (O6.2.C)
- [ ] Add event details dialog/bottom sheet (O6.2.C)
- [ ] Wire up to EventLogRepo data (O6.2.C)

### Phase 3: Testing
- [ ] Write widget tests for offline banner (O6.4)
- [ ] Write widget tests for sync button (O6.4)
- [ ] Write widget tests for status pills (O6.4)

---

## 📝 No Supabase Changes Needed

✅ All data already exists in local database (Drift)
✅ No new API endpoints needed
✅ No SQL changes required

---

## 🧪 Testing Commands

After implementation, you'll run:

```powershell
# Test offline banner widget
flutter test test/widgets/offline_banner_test.dart

# Test event history widget
flutter test test/widgets/event_history_list_test.dart

# Test sync button widget
flutter test test/widgets/sync_button_test.dart

# Run all widget tests
flutter test test/widgets/

# Run all tests
flutter test
```

**Expected Output**:
```
✓ Offline banner appears when offline
✓ Offline banner disappears when online
✓ Pending count updates correctly
✓ Sync button disabled when offline
✓ Sync button shows loading state
✓ Event status pills have correct colors
All tests passed!
```

---

## 🎯 Summary

**Already Exists**:
- ✅ Sync Now button (needs enhancement)
- ✅ Activity log
- ✅ Connectivity logging
- ✅ Status cards

**Needs to be Added**:
- ❌ Offline banner (visual indicator at top)
- ❌ Pending event count card
- ❌ Last sync timestamp display
- ❌ Event history list with status pills
- ❌ Enhanced sync button (loading, disabled when offline, reconciliation)
- ❌ Widget tests

**Priority Order**:
1. **High**: Offline banner + Enhanced sync button
2. **Medium**: Pending count + Last sync time
3. **Low**: Event history with status pills

