# O4.4 - Backend Testing Guide

Complete testing guide for verifying the Supabase backend integration.

## Prerequisites Checklist
- [x] Supabase project created
- [x] `supabase_setup.sql` executed successfully
- [x] Geofence coordinates updated to your location
- [x] `lib/config/supabase_config.dart` configured with URL and anon key
- [x] `flutter pub get` completed
- [x] App shows "Supabase initialized successfully" in logs

---

## Part 1: Supabase SQL Tests (Backend Validation)

### Step 1: Update Test Coordinates
Before running any tests, find your current location coordinates:
1. Open Google Maps
2. Right-click on your location → Click the coordinates
3. Note your latitude and longitude (e.g., `14.5995, 120.9842`)

### Step 2: Run SQL Tests in Supabase
Open `supabase_tests.sql` and:
1. **Replace ALL instances** of `<YOUR_LAT>` with your latitude
2. **Replace ALL instances** of `<YOUR_LNG>` with your longitude
3. Copy each test section and paste into Supabase SQL Editor
4. Click "Run" for each test

### Expected Results:

#### TEST 1: Idempotency Check ✓
**First call:**
```json
{
  "status": "CONFIRMED",
  "reason": "Event validated successfully",
  "event_id": "some-uuid",
  "duplicate": false
}
```
**Second call (same dedupe_key):**
```json
{
  "status": "CONFIRMED",
  "reason": "Event already processed",
  "event_id": "same-uuid-as-first",
  "duplicate": true
}
```
**Row count check:** Should be exactly `1`

#### TEST 2: Geofence Rejection ✓
```json
{
  "status": "REJECTED",
  "reason": "GEOFENCE_VIOLATION: Location outside geofence",
  "event_id": "some-uuid",
  "duplicate": false
}
```

#### TEST 3: Biometric Freshness Rejection ✓
```json
{
  "status": "REJECTED",
  "reason": "BIOMETRIC_STALE: Biometric verification too old",
  "event_id": "some-uuid",
  "duplicate": false
}
```

#### TEST 4: Sequence Validation ✓
**First sign-in:** `status: "CONFIRMED"`
**Second sign-in without sign-out:**
```json
{
  "status": "REJECTED",
  "reason": "DUPLICATE_EVENT: Cannot perform same action twice in a row",
  "event_id": "some-uuid",
  "duplicate": false
}
```

#### TEST 5: Heartbeat ✓
```json
{
  "status": "CONFIRMED",
  "reason": "Heartbeat recorded successfully",
  "event_id": "some-uuid",
  "duplicate": false
}
```

#### TEST 6: Accuracy Rejection ✓
```json
{
  "status": "REJECTED",
  "reason": "POOR_ACCURACY: Location accuracy too poor",
  "event_id": "some-uuid",
  "duplicate": false
}
```

### Step 3: View All Test Results
Run the summary query at the end of `supabase_tests.sql`:
```sql
select 
  event_type,
  status,
  server_reason,
  dedupe_key,
  created_at
from public.attendance_events
where dedupe_key like 'test_%'
order by created_at desc;
```

**Expected:** Should show all test events with their respective statuses (CONFIRMED/REJECTED)

---

## Part 2: Flutter Integration Tests

### Run E2E Tests
```powershell
flutter test test/integration/e2e_sync_test.dart
```

**Expected Output:**
```
00:02 +4: All tests passed!
```

**What these tests verify:**
- ✓ Offline event capture → PENDING status
- ✓ Event queued in outbox
- ✓ Sync operation dequeues items
- ✓ Status updated to CONFIRMED after sync
- ✓ Outbox cleared after successful sync
- ✓ REJECTED events marked with server reason
- ✓ Retry behavior with backoff
- ✓ Deduplication prevents duplicates

### Run All Tests
```powershell
flutter test
```

**Expected:** All tests should pass (minor UI test warnings are OK)

---

## Part 3: Manual App Testing (Real E2E Flow)

### Test 1: Offline Capture with Successful Sync

1. **Start the app:**
   ```powershell
   flutter run
   ```

2. **Set up session:**
   - Tap "Set Event Time" → Choose current time window
   - Tap "Set Geofence" → Use your current location
   - Verify you're inside the geofence (check map)

3. **Turn OFF internet** (WiFi and mobile data)

4. **Perform sign-in:**
   - Tap "Check In"
   - Complete biometric authentication
   - **Expected logs:**
     ```
     Sign-in event captured and enqueued
     Event appended | event_id: xxx, type: ATTEND_IN, status: PENDING
     Outbox item enqueued | event_id: xxx, dedupe_key: xxx
     ```

5. **Turn ON internet**

6. **Tap "Sync Now"**
   - **Expected logs:**
     ```
     Manual sync triggered
     Starting sync operation
     Processing sync batch | item_count: 1
     Item synced successfully | server_status: CONFIRMED
     Event status updated | new_status: CONFIRMED
     ```

7. **Verify in Supabase:**
   ```sql
   select event_type, status, server_reason, location_lat, location_lng
   from public.attendance_events
   order by created_at desc
   limit 1;
   ```
   **Expected:** Event with status='CONFIRMED'

### Test 2: Geofence Rejection

1. **Move far from geofence** (or set geofence at a different location)

2. **Turn OFF internet**

3. **Perform sign-in:**
   - Should capture locally as PENDING

4. **Turn ON internet**

5. **Tap "Sync Now"**
   - **Expected logs:**
     ```
     Item synced successfully | server_status: REJECTED
     Event status updated | new_status: REJECTED, server_reason: GEOFENCE_VIOLATION
     ```

6. **Verify in Supabase:**
   ```sql
   select status, server_reason
   from public.attendance_events
   order by created_at desc
   limit 1;
   ```
   **Expected:** status='REJECTED', reason contains 'GEOFENCE_VIOLATION'

### Test 3: Automatic Sync on Connectivity Regain

1. **Turn OFF internet**

2. **Perform sign-in** → Captured as PENDING

3. **Turn ON internet**

4. **Wait 60 seconds** (for automatic sync timer)
   - **Expected logs:**
     ```
     Connectivity regained, triggering sync
     Starting sync operation
     Item synced successfully
     ```

---

## Part 4: Verification Checklist

### Backend Tests (Supabase SQL)
- [ ] Idempotency test passed (duplicate=true on second call)
- [ ] Only 1 row created for duplicate dedupe_key
- [ ] Geofence rejection works correctly
- [ ] Biometric freshness validation works
- [ ] Sequence validation prevents double sign-in
- [ ] Heartbeat records successfully
- [ ] Accuracy threshold enforced

### Integration Tests (Flutter)
- [ ] E2E sync test passes
- [ ] Offline capture creates PENDING events
- [ ] Outbox queues items correctly
- [ ] Sync updates event status
- [ ] REJECTED events marked with reason
- [ ] Retry behavior works
- [ ] Deduplication prevents duplicates

### Manual App Tests
- [ ] Offline sign-in captured as PENDING
- [ ] Online sync updates to CONFIRMED
- [ ] Geofence rejection works in real-time
- [ ] Auto-sync triggers on connectivity regain
- [ ] "Sync Now" button works
- [ ] Events visible in Supabase dashboard

---

## Troubleshooting

### Issue: "Supabase not configured" in logs
**Solution:** Update `lib/config/supabase_config.dart` with your actual URL and anon key

### Issue: All events REJECTED with GEOFENCE_VIOLATION
**Solution:** Update session geofence to your current location:
```sql
update public.sessions
set geofence_center = ST_SetSRID(ST_MakePoint(<YOUR_LNG>, <YOUR_LAT>), 4326)::geography
where id = '550e8400-e29b-41d4-a716-446655440002';
```

### Issue: SQL tests fail with "function does not exist"
**Solution:** Re-run `supabase_setup.sql` completely

### Issue: Flutter tests fail with "binding not initialized"
**Solution:** This is expected for location-based tests in CI environment - focus on manual app tests

### Issue: Sync shows "Network error" even when online
**Solution:** Check Supabase URL and anon key are correct, verify project is not paused

---

## Success Criteria

All of the following should be true:

✅ **Backend (SQL tests):**
- Idempotency works (no duplicate server records)
- Geofence validation rejects events outside radius
- All 6 rule validations work correctly
- Both RPCs (validate_attendance, record_heartbeat) return proper responses

✅ **Integration (Flutter tests):**
- All E2E tests pass
- Offline→Online flow completes successfully
- Event statuses update correctly

✅ **Manual (Real app):**
- Offline events sync to Supabase when online
- Server validations match local rules
- Events visible in Supabase dashboard with correct statuses
- "Sync Now" button triggers immediate sync

---

## Next Steps After O4.4

Once all tests pass, you're ready for:
- **O5 - Reconciliation**: Pull authoritative server statuses to keep local database in sync
- **O6 - UI Indicators**: Add offline banner, pending count, status pills
- **O7 - Observability**: Enhanced logging and metrics
- **O8 - Retry Hardening**: Production-ready error handling
- **O9 - Demo Script**: Complete walkthrough for thesis defense

---

## Quick Reference

**Test User ID:** `550e8400-e29b-41d4-a716-446655440000`  
**Test Device ID:** `550e8400-e29b-41d4-a716-446655440001`  
**Test Session ID:** `550e8400-e29b-41d4-a716-446655440002`

**Key Endpoints:**
- Attendance: `/api/attendance/validate` → `public.validate_attendance()`
- Heartbeat: `/api/heartbeat/record` → `public.record_heartbeat()`

**Rule Thresholds:**
- Location accuracy: ≤ 50m
- Biometric freshness: ≤ 5 minutes
- Geofence radius: 100m (configurable)

