# ✅ Offline Mode Testing Checklist

Use this checklist to verify all offline mode features are working correctly.

---

## 🏗️ Infrastructure Tests

### Database & Repositories
- [ ] Run `flutter test test/data/local/event_log_repo_test.dart`
- [ ] Run `flutter test test/data/local/outbox_repo_test.dart`
- [ ] Verify event_log table exists
- [ ] Verify outbox table with unique dedupe_key
- [ ] Verify sync_cursor table exists

### Local Rules Engine
- [ ] Run `flutter test test/domain/local_rules_test.dart`
- [ ] Test geofence validation (inside/outside)
- [ ] Test time window validation
- [ ] Test accuracy threshold
- [ ] Test biometric freshness
- [ ] Test sequence validation (no double sign-in)
- [ ] Test trusted device check

### Services
- [ ] Run `flutter test test/domain/attendance_service_test.dart`
- [ ] Run `flutter test test/domain/heartbeat_service_test.dart`
- [ ] Run `flutter test test/services/logging_service_test.dart`
- [ ] Run `flutter test test/services/metrics_service_test.dart`

### Sync & Retry
- [ ] Run `flutter test test/sync/backoff_calculator_test.dart`
- [ ] Run `flutter test test/sync/error_handling_test.dart`
- [ ] Run `flutter test test/integration/idempotency_test.dart`
- [ ] Verify exponential backoff with jitter
- [ ] Verify 5xx errors are retryable
- [ ] Verify 4xx errors are not retryable

### Reconciliation
- [ ] Run `flutter test test/domain/reconcile_service_test.dart`
- [ ] Test server-to-client status updates
- [ ] Test idempotent reconciliation

### UI Components
- [ ] Run `flutter test test/widgets/offline_banner_test.dart`
- [ ] Run `flutter test test/widgets/event_status_card_test.dart`
- [ ] Run `flutter test test/widgets/event_history_list_test.dart`

**Command to run all tests:**
```powershell
flutter test
```

**Expected:** All tests pass (100+ tests)

---

## 🌐 Backend Tests (Supabase)

### Idempotency
- [ ] Run duplicate dedupe_key test in Supabase SQL Editor
- [ ] Verify only ONE row created for duplicate requests
- [ ] Check `duplicate: true` returned on second call

### Rule Validation
- [ ] Test geofence rejection (lat=0, lng=0)
- [ ] Test biometric staleness (timestamp > 5 min old)
- [ ] Test duplicate sign-in (two ATTEND_IN without ATTEND_OUT)
- [ ] Test accuracy rejection (accuracy > 50m)
- [ ] Test time window (before starts_at or after ends_at)

### Heartbeats
- [ ] Test heartbeat recording (no biometric required)
- [ ] Verify heartbeat idempotency
- [ ] Check heartbeats auto-confirmed

**Refer to:** `supabase_tests.sql` for all backend tests

---

## 📱 Manual App Testing

### 1. Basic Attendance Flow
- [ ] Launch app
- [ ] Tap "Check In"
- [ ] Authenticate with biometric
- [ ] Event appears with PENDING status
- [ ] Event syncs to CONFIRMED within 30s
- [ ] Tap "Check Out"
- [ ] Authenticate with biometric
- [ ] Second event syncs successfully

### 2. Offline Mode
- [ ] Enable Airplane Mode
- [ ] Offline banner appears at top
- [ ] Tap "Check In" while offline
- [ ] Event captured locally (PENDING)
- [ ] Event persists in history
- [ ] Try "Sync Now" - shows error
- [ ] Disable Airplane Mode
- [ ] Offline banner disappears
- [ ] Auto-sync triggers within seconds
- [ ] Event changes to CONFIRMED

### 3. App Restart (Persistence)
- [ ] Create offline event (airplane mode)
- [ ] Force close app (swipe away)
- [ ] Reopen app
- [ ] Event still visible with PENDING status
- [ ] Go online
- [ ] Event syncs successfully

### 4. Multiple Offline Events
- [ ] Enable Airplane Mode
- [ ] Create 3 events (check-in, check-out, check-in)
- [ ] All show PENDING
- [ ] Pending count shows "3 pending"
- [ ] Go online
- [ ] All 3 sync in batch
- [ ] Pending count drops to "0 pending"

### 5. Geofence Validation
- [ ] **In Emulator:** Set location to 0.0, 0.0
- [ ] **On Device:** Move outside geofence OR spoof GPS
- [ ] Attempt check-in
- [ ] Event syncs as REJECTED
- [ ] Red pill appears with reason
- [ ] Tap event to see full error message
- [ ] Reset location to valid coordinates

### 6. Sequence Validation
- [ ] Check in successfully (CONFIRMED)
- [ ] Try to check in again (without check out)
- [ ] Event syncs as REJECTED
- [ ] Reason: "DUPLICATE_EVENT" or "Cannot perform same action twice"

### 7. Background Heartbeats
- [ ] Check in successfully
- [ ] Tap "START" on map screen
- [ ] Foreground notification appears
- [ ] Wait 1-2 minutes
- [ ] Check event history
- [ ] See HEARTBEAT events every ~60s
- [ ] Tap "STOP"
- [ ] No more heartbeats generated

### 8. Sync Now Button
- [ ] Create offline event
- [ ] Tap "Sync Now" while offline
- [ ] Shows error message
- [ ] Go online
- [ ] Tap "Sync Now"
- [ ] Event syncs immediately
- [ ] Success message appears

### 9. Status Pills & Indicators
- [ ] Verify PENDING = yellow pill
- [ ] Verify CONFIRMED = green pill
- [ ] Verify REJECTED = red pill
- [ ] Tap each pill to see tooltip/details
- [ ] Check pending count badge accuracy
- [ ] Verify last sync timestamp updates

### 10. Dev Profile
- [ ] Tap purple developer icon
- [ ] Dev Profile opens
- [ ] Summary stats show correct numbers
- [ ] Metrics organized by category
- [ ] Tap "Dump Logs" - clipboard has JSON
- [ ] Tap "Export Metrics" - clipboard has JSON
- [ ] Tap "Trigger Sync" - sync happens
- [ ] Tap "Reset Counters" - metrics → 0
- [ ] Tap "Clear Logs" - logs deleted
- [ ] Auto-refresh works (pause/resume)

---

## 🔄 Edge Cases

### Network Flapping
- [ ] Start sync
- [ ] Turn off Wi-Fi mid-sync
- [ ] Turn on Wi-Fi
- [ ] Sync retries and completes

### Low Battery / Background
- [ ] Create event
- [ ] Lock device
- [ ] Wait for background sync
- [ ] Unlock device
- [ ] Event synced

### Time Zone Changes
- [ ] Create events
- [ ] Change device time zone
- [ ] Events still sync correctly
- [ ] Timestamps display properly

### Storage Full
- [ ] (Hard to test, but code handles gracefully)
- [ ] Database writes should fail gracefully
- [ ] App shouldn't crash

### Biometric Failures
- [ ] Try check-in with failed biometric
- [ ] Event should NOT be created
- [ ] Try 3 times (lockout)
- [ ] App handles gracefully

---

## 📊 Performance Tests

### Sync Performance
- [ ] Create 10 offline events
- [ ] Go online
- [ ] All 10 sync in < 30 seconds
- [ ] Check `sync.batch_processed` metric

### Database Performance
- [ ] Create 100 events over time
- [ ] App remains responsive
- [ ] Event list loads quickly
- [ ] No lag in UI

### Memory Usage
- [ ] Run app for 30 minutes
- [ ] Check memory usage (Android Studio Profiler)
- [ ] No memory leaks
- [ ] Logs don't grow unbounded (capped at 100)

---

## 🔒 Security Tests

### Biometric Enforcement
- [ ] Check-in requires biometric
- [ ] Check-out requires biometric
- [ ] Heartbeats do NOT require biometric
- [ ] Biometric timestamp captured
- [ ] Stale biometric rejected (> 5 min)

### Data Isolation
- [ ] Events are user-specific
- [ ] Can't access other users' events
- [ ] RLS policies enforce isolation (Supabase)

### Secure Storage
- [ ] No sensitive data in logs
- [ ] Logs don't contain passwords/tokens
- [ ] Database file is app-private

---

## 📝 Documentation Tests

### README Files
- [ ] README.md exists and is up-to-date
- [ ] E2E_DEMO_SCRIPT.md is complete
- [ ] QUICK_START_GUIDE.md works
- [ ] O1-O8 summary docs exist

### Code Comments
- [ ] All major classes have doc comments
- [ ] Complex logic is explained
- [ ] Public APIs are documented

### Feature Flags
- [ ] FEATURE_FLAGS_README.md is accurate
- [ ] All flags are documented
- [ ] Default values are sensible

---

## ✅ Final Verification

Run this comprehensive check before considering complete:

```powershell
# 1. Clean build
flutter clean
flutter pub get

# 2. Run all tests
flutter test

# 3. Run app
flutter run

# 4. Quick smoke test
#    - Check in (online) → CONFIRMED
#    - Check out (offline) → PENDING → CONFIRMED
#    - Open Dev Profile → Export logs

# 5. Verify Supabase
#    - Run idempotency test
#    - Check event count matches UI
```

**If all pass:** 🎉 **System is production-ready!**

---

## 🐛 Known Issues / Limitations

Document any known issues here:

- [ ] None currently (or list specific issues)

---

## 📅 Test Results

**Date Tested:** _____________  
**Tested By:** _____________  
**Device/Emulator:** _____________  
**Android Version:** _____________  
**App Version:** _____________

**Overall Result:** ☐ PASS ☐ FAIL

**Notes:**
```
(Add any observations or issues encountered)
```

---

## 🚀 Sign-Off

By completing this checklist, you verify that:

✅ All automated tests pass  
✅ All manual tests pass  
✅ Backend validation works  
✅ Offline mode is fully functional  
✅ UI indicators are accurate  
✅ Dev tools work correctly  
✅ Documentation is complete  

**Ready for production!** 🎉

