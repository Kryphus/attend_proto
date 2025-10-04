# 🎬 End-to-End Demo Script - TagMeIn+ Offline Mode

## Overview

This script demonstrates the complete offline-first attendance tracking system, showcasing all major features from O1-O8.

**Duration:** ~15 minutes  
**Prerequisites:** 
- App installed on Android device/emulator
- Supabase backend configured
- Test session created (see Setup section)

---

## 📋 Setup (Before Demo)

### 1. **Verify Supabase Setup**

Ensure your test session coordinates match your physical location:

```sql
-- Check current test session
SELECT 
  name,
  ST_Y(geofence_center::geometry) as lat,
  ST_X(geofence_center::geometry) as lng,
  geofence_radius_m as radius_meters,
  starts_at,
  ends_at
FROM public.sessions 
WHERE id = '550e8400-e29b-41d4-a716-446655440002';
```

**Update if needed:**
```sql
UPDATE public.sessions
SET 
  geofence_center = ST_SetSRID(ST_MakePoint(<YOUR_LNG>, <YOUR_LAT>), 4326)::geography,
  starts_at = now() - interval '1 hour',
  ends_at = now() + interval '8 hours'
WHERE id = '550e8400-e29b-41d4-a716-446655440002';
```

### 2. **Clean Test Data**

```sql
-- Clear previous test events
DELETE FROM public.attendance_events 
WHERE user_id = '550e8400-e29b-41d4-a716-446655440000';

-- Verify clean slate
SELECT count(*) FROM public.attendance_events 
WHERE user_id = '550e8400-e29b-41d4-a716-446655440000';
-- Should return: 0
```

### 3. **Launch App**

```powershell
flutter run
```

**Expected:** App launches with empty event history

---

## 🎯 Demo Scenarios

---

## **Scenario 1: Normal Online Sign-In** ✅

**Goal:** Show successful attendance capture with immediate sync

### Steps:

1. **Verify Online Status**
   - ✅ No offline banner visible at top
   - ✅ Connection indicator shows online

2. **Tap "Check In" Button**
   - 🔐 Biometric prompt appears
   - 👆 Authenticate with fingerprint/face

3. **Observe Event Creation**
   - ⏱️ Status shows "PENDING" (yellow pill)
   - 📊 Pending count shows "1 pending"
   - 📝 Event appears in history with timestamp

4. **Wait for Auto-Sync** (≤30 seconds)
   - OR tap "Sync Now" button for immediate sync
   - 🔄 Sync animation plays

5. **Verify Confirmation**
   - ✅ Status changes to "CONFIRMED" (green pill)
   - 📊 Pending count shows "0 pending"
   - 💬 Reason: "Event validated successfully"

6. **Check Dev Profile** (Optional)
   - Tap purple developer icon (⚙️)
   - See metrics:
     - `capture.sign_in`: 1
     - `capture.success`: 1
     - `event.confirmed`: 1
     - `outbox.sync_success`: 1

**Expected Result:** ✅ Event goes PENDING → CONFIRMED in ≤30s

---

## **Scenario 2: Offline Sign-Out → Online Sync** 📵➡️🌐

**Goal:** Demonstrate offline capture with delayed sync

### Steps:

1. **Enable Airplane Mode**
   - Open device quick settings
   - ✈️ Turn ON Airplane Mode
   - ⚠️ Offline banner appears: "You're offline. Events will sync when reconnected."

2. **Tap "Check Out" Button**
   - 🔐 Biometric prompt appears
   - 👆 Authenticate

3. **Observe Offline Capture**
   - ⏱️ Status shows "PENDING" (yellow pill)
   - 📊 Pending count shows "1 pending"
   - ⚠️ Offline banner still visible
   - 💬 "Event will sync when online"

4. **Try Manual Sync (Will Fail)**
   - Tap "Sync Now" button
   - ⚠️ Shows error: "Sync failed: no network"
   - ⏱️ Event remains "PENDING"

5. **Disable Airplane Mode**
   - ✈️ Turn OFF Airplane Mode
   - ⏳ Wait 2-3 seconds for connectivity detection
   - ✅ Offline banner disappears

6. **Auto-Sync Triggers**
   - 🔄 Automatic sync starts (on connectivity regain)
   - OR tap "Sync Now" if needed

7. **Verify Confirmation**
   - ✅ Status changes to "CONFIRMED" (green pill)
   - 📊 Pending count shows "0 pending"
   - 💬 Reason: "Event validated successfully"

8. **Check Server** (Optional)
   ```sql
   SELECT event_type, status, server_reason, created_at
   FROM public.attendance_events
   WHERE user_id = '550e8400-e29b-41d4-a716-446655440000'
   ORDER BY created_at DESC
   LIMIT 2;
   ```
   **Expected:** Both ATTEND_IN and ATTEND_OUT with status='CONFIRMED'

**Expected Result:** ✅ Event syncs automatically after network restored

---

## **Scenario 3: Geofence Violation → Rejection** ❌

**Goal:** Show server-side rule validation rejecting invalid event

### Steps:

1. **Simulate Location Outside Geofence**
   
   **Option A - Android Emulator:**
   - Open "Extended Controls" (⋮ menu)
   - Go to "Location" tab
   - Set coordinates far from geofence:
     - Example: 0.0, 0.0 (middle of ocean)
   - Click "Send"

   **Option B - Physical Device:**
   - Use a location spoofing app (developer settings)
   - Or physically move outside the geofence radius

2. **Verify New Location**
   - Map marker should update to new position
   - Or check tracking logs for new coordinates

3. **Attempt Sign-In**
   - Tap "Check In" button
   - 🔐 Authenticate with biometric
   - ⏱️ Event shows "PENDING" initially

4. **Wait for Sync**
   - Auto-sync occurs (≤30s)
   - OR tap "Sync Now"

5. **Observe Rejection**
   - ❌ Status changes to "REJECTED" (red pill)
   - 📊 Pending count remains "0"
   - 💬 Reason: "GEOFENCE_VIOLATION: Location outside geofence"
   - 🔍 Tap event to see full rejection details

6. **Check Server** (Optional)
   ```sql
   SELECT 
     event_type, 
     status, 
     server_reason,
     location_lat,
     location_lng
   FROM public.attendance_events
   WHERE user_id = '550e8400-e29b-41d4-a716-446655440000'
   ORDER BY created_at DESC
   LIMIT 1;
   ```
   **Expected:** status='REJECTED', server_reason contains 'GEOFENCE_VIOLATION'

7. **Reset Location** (For Next Test)
   - Set coordinates back inside geofence
   - Verify map marker returns to valid area

**Expected Result:** ❌ Server rejects event, shows rejection reason in UI

---

## **Scenario 4: Duplicate Prevention (Idempotency)** 🛡️

**Goal:** Prove system prevents duplicate events

### Steps:

1. **Create Event (Online)**
   - Ensure online
   - Tap "Check In"
   - Authenticate
   - ⏱️ Event shows "PENDING"

2. **Note Event Details**
   - Remember the timestamp (to identify this event)
   - Example: "Check In at 2:30 PM"

3. **Simulate App Crash Before Sync**
   - Stop the app (swipe away or force stop)
   - **Don't wait for sync!**

4. **Check Database**
   ```powershell
   flutter run
   ```
   - Open Dev Profile
   - Or check outbox manually:
     ```dart
     // In debug console
     final items = await outboxRepo.getAllItems();
     print('Outbox items: ${items.length}');
     ```
   - Should see 1 item in outbox

5. **Restart App**
   - App loads existing event from local DB
   - Event still shows "PENDING"
   - Outbox still contains the event

6. **Sync Occurs**
   - Auto-sync or manual "Sync Now"
   - First attempt: Creates server event
   - Second attempt (retry): Server returns duplicate=true

7. **Verify Single Server Record**
   ```sql
   SELECT count(*) as total_events
   FROM public.attendance_events
   WHERE user_id = '550e8400-e29b-41d4-a716-446655440000'
   AND event_type = 'ATTEND_IN'
   AND event_timestamp >= now() - interval '5 minutes';
   ```
   **Expected:** count = 1 (not 2!)

8. **Check Metrics**
   - Open Dev Profile
   - See `outbox.duplicate`: Should be 0 or 1
   - See `api.call_success`: Shows successful calls

**Expected Result:** ✅ Only ONE event on server despite multiple sync attempts

---

## **Scenario 5: Retry with Exponential Backoff** 🔄

**Goal:** Show automatic retry with increasing delays

### Steps:

1. **Prepare for Network Interruption**
   - Ensure online
   - Tap "Check In"
   - Authenticate

2. **Immediately Enable Airplane Mode**
   - As soon as event is PENDING
   - Before first sync attempt occurs

3. **Observe Failed Sync Attempts**
   - Check Dev Profile → Metrics
   - `sync.attempt`: Increases
   - `sync.failure`: Increases
   - `api.retryable_error`: Increases

4. **Check Outbox Item**
   - In Dev Profile, note:
   - `attempts`: Increments (1, 2, 3...)
   - `next_attempt_at`: Increases exponentially
     - Attempt 1: ~30s
     - Attempt 2: ~60s
     - Attempt 3: ~120s

5. **View Tracking Logs**
   - Main screen → Scroll tracking logs
   - Look for backoff messages:
     ```
     ⚠️ [SyncWorker] Backoff applied after failure
     ⏱️ [BackoffCalculator] delay_ms: 30000
     ```

6. **Re-enable Network After 3+ Attempts**
   - Turn off Airplane Mode
   - Auto-sync triggers

7. **Verify Success**
   - ✅ Event confirmed
   - Check metrics:
     - `sync.success`: +1
     - `outbox.sync_success`: +1
     - `outbox.retry`: Shows number of retries

**Expected Result:** ✅ System retries with increasing delays until success

---

## **Scenario 6: Heartbeat Tracking (Background)** 💓

**Goal:** Show automatic heartbeat generation during active session

### Steps:

1. **Sign In Successfully**
   - Online mode
   - Tap "Check In"
   - Authenticate
   - Wait for CONFIRMED

2. **Start Session**
   - Tap "START" button on map screen
   - Foreground service notification appears
   - Background tracking begins

3. **Wait 1-2 Minutes**
   - Heartbeats generate every minute
   - Check event history for HEARTBEAT events

4. **Observe Heartbeats**
   - 💓 Type: "HEARTBEAT"
   - ⏱️ Status: Usually auto-confirmed
   - 📍 Each has location data
   - ⏰ Timestamps ~1 min apart

5. **Check Dev Profile Metrics**
   - `capture.heartbeat`: Increases each minute
   - `event.confirmed`: Includes heartbeats
   - `outbox.sync_success`: Shows heartbeat syncs

6. **Stop Session**
   - Tap "STOP" button
   - Foreground service stops
   - No more heartbeats

7. **Verify Server** (Optional)
   ```sql
   SELECT 
     event_type,
     event_timestamp,
     status
   FROM public.attendance_events
   WHERE user_id = '550e8400-e29b-41d4-a716-446655440000'
   AND event_type = 'HEARTBEAT'
   ORDER BY event_timestamp DESC
   LIMIT 5;
   ```
   **Expected:** Multiple heartbeat records ~1 min apart

**Expected Result:** ✅ Heartbeats generated and synced automatically

---

## **Scenario 7: Reconciliation (Server Overrides Local)** 🔁

**Goal:** Demonstrate server-to-client status sync

### Steps:

1. **Create Pending Event**
   - Offline mode
   - Sign in
   - Event shows PENDING locally

2. **Manually Reject on Server**
   ```sql
   -- Find the event
   SELECT id, client_event_id, status
   FROM public.attendance_events
   WHERE user_id = '550e8400-e29b-41d4-a716-446655440000'
   AND status = 'CONFIRMED'
   ORDER BY created_at DESC
   LIMIT 1;

   -- Manually reject it (simulate server-side decision)
   UPDATE public.attendance_events
   SET 
     status = 'REJECTED',
     server_reason = 'MANUAL_REJECT: Testing reconciliation',
     updated_at = now()
   WHERE id = '<event-id-from-above>';
   ```

3. **Trigger Reconciliation**
   - In app, open Dev Profile
   - Tap "Trigger Sync" (includes reconciliation)
   - OR wait for automatic reconciliation

4. **Observe Status Update**
   - ❌ Local event flips from CONFIRMED to REJECTED
   - 💬 Reason updates: "MANUAL_REJECT: Testing reconciliation"
   - 📊 Metrics update

5. **Check Metrics**
   - `reconcile.attempt`: +1
   - `reconcile.success`: +1
   - `reconcile.events_updated`: +1

**Expected Result:** ✅ Local state updated to match server truth

---

## **Scenario 8: Dev Profile Dashboard** 📊

**Goal:** Showcase observability features

### Steps:

1. **Open Dev Profile**
   - Tap purple developer icon (⚙️)
   - Dashboard opens

2. **Review Summary Stats**
   - Total Events
   - Success Rate (%)
   - Pending Count
   - Synced Count

3. **Explore Metrics by Category**
   - 📥 Capture: sign_in, sign_out, heartbeat counts
   - ✅ Rules: pass/violation counts
   - 📤 Outbox: enqueued, synced, retries
   - 🔄 Sync: attempts, success, failure
   - 📊 Events: pending, confirmed, rejected
   - 🌐 API: successes, failures, retryable errors
   - 🔁 Reconcile: attempts, updates

4. **Export Logs**
   - Tap "Dump Logs" button
   - ✅ Confirmation: "Last 100 logs copied!"
   - Paste into text editor to inspect JSON

5. **Export Metrics**
   - Tap "Export Metrics" button
   - ✅ Confirmation: "Metrics exported!"
   - Paste to see structured JSON

6. **Manual Sync**
   - Tap "Trigger Sync" button
   - Watch metrics update in real-time
   - Auto-refresh every 2 seconds

7. **Reset Counters**
   - Tap "Reset Counters"
   - Confirm dialog
   - All metrics → 0
   - Logs preserved

8. **Clear Logs**
   - Tap "Clear Logs"
   - Confirm dialog
   - Logs deleted
   - Metrics preserved

**Expected Result:** ✅ Full observability and debug control

---

## 📸 Screenshot Checklist

Capture these key moments:

- [ ] Empty state (clean start)
- [ ] Online check-in → PENDING
- [ ] PENDING → CONFIRMED transition
- [ ] Offline banner visible
- [ ] Offline event captured (PENDING)
- [ ] REJECTED event with reason
- [ ] Event history with all 3 statuses
- [ ] Dev Profile dashboard
- [ ] Metrics by category
- [ ] Exported logs JSON
- [ ] Exported metrics JSON

---

## 🐛 Troubleshooting

### Event Stuck in PENDING
- Check network connection
- Tap "Sync Now" manually
- Check Dev Profile → API errors
- Verify Supabase is running

### All Events REJECTED
- Check geofence coordinates match your location
- Verify session time window is active
- Check biometric timestamp freshness
- Review server_reason for specific error

### Sync Not Triggering
- Check `FeatureFlags.syncInterval` (default 30s)
- Verify `FeatureFlags.enableOfflineMode` is true
- Check connectivity state
- Restart app to reset timers

### Heartbeats Not Generating
- Ensure session is STARTED
- Check foreground service notification
- Verify location permissions
- Check `FeatureFlags.heartbeatInterval` (default 60s)

---

## 📝 Demo Tips

1. **Rehearse First:** Run through once before live demo
2. **Clean Data:** Always start with clean Supabase tables
3. **Stable Network:** Use Wi-Fi, not cellular (for airplane mode reliability)
4. **Visual Aids:** Project screen or use screen mirroring
5. **Narrate:** Explain what's happening while waiting for syncs
6. **Backup Plan:** Have pre-recorded screen captures as backup

---

## ✅ Success Criteria

After completing all scenarios, you should have demonstrated:

- ✅ Offline event capture with local persistence
- ✅ Automatic sync when network restored
- ✅ Server-side rule validation (geofence, biometric, etc.)
- ✅ Event status updates (PENDING → CONFIRMED/REJECTED)
- ✅ Retry with exponential backoff
- ✅ Idempotent API calls (no duplicates)
- ✅ Real-time UI indicators (offline banner, status pills)
- ✅ Background heartbeat tracking
- ✅ Server-to-client reconciliation
- ✅ Comprehensive metrics and logging

**🎉 Complete offline-first system demonstrated!**

