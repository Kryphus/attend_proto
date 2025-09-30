-- =====================================================
-- O4.4 - BACKEND TESTS FOR SUPABASE
-- Copy-paste each section into Supabase SQL Editor
-- =====================================================

-- IMPORTANT: Replace <YOUR_LAT> and <YOUR_LNG> with coordinates 
-- INSIDE your geofence (e.g., your current location)
-- Example: If your geofence center is at 14.5995, 120.9842
-- Use something like: 14.5996, 120.9843 (slightly offset but inside radius)

-- =====================================================
-- TEST 1: IDEMPOTENCY CHECK (Duplicate dedupe_key)
-- Expected: First call creates event (duplicate=false)
--           Second call returns same event (duplicate=true)
-- =====================================================

-- First call - should create new event
select public.validate_attendance(
  jsonb_build_object(
    'user_id', '550e8400-e29b-41d4-a716-446655440000',
    'device_id', '550e8400-e29b-41d4-a716-446655440001',
    'session_id', '550e8400-e29b-41d4-a716-446655440002',
    'event_type', 'ATTEND_IN',
    'timestamp', now(),
    'location', jsonb_build_object(
      'lat', 6.682057,    -- REPLACE with your latitude
      'lng', 125.353906,    -- REPLACE with your longitude
      'accuracy', 10.0
    ),
    'biometric_ok', true,
    'biometric_timestamp', now(),
    'dedupe_key', 'test_idempotency_key_001',
    'client_event_id', '00000000-0000-0000-0000-000000000001'
  )
);

-- Expected output (first call):
-- {
--   "status": "CONFIRMED",
--   "reason": "Event validated successfully",
--   "event_id": "<some-uuid>",
--   "duplicate": false
-- }

-- =====================================================
-- Run the SAME call again (idempotency test)
-- =====================================================

select public.validate_attendance(
  jsonb_build_object(
    'user_id', '550e8400-e29b-41d4-a716-446655440000',
    'device_id', '550e8400-e29b-41d4-a716-446655440001',
    'session_id', '550e8400-e29b-41d4-a716-446655440002',
    'event_type', 'ATTEND_IN',
    'timestamp', now(),
    'location', jsonb_build_object(
      'lat', 6.682057,    -- SAME coordinates
      'lng', 125.353906,    -- SAME coordinates
      'accuracy', 10.0
    ),
    'biometric_ok', true,
    'biometric_timestamp', now(),
    'dedupe_key', 'test_idempotency_key_001',  -- SAME dedupe_key
    'client_event_id', '00000000-0000-0000-0000-000000000001'
  )
);

-- Expected output (second call):
-- {
--   "status": "CONFIRMED",
--   "reason": "Event already processed",
--   "event_id": "<same-uuid-as-first>",
--   "duplicate": true    <-- This should be TRUE
-- }

-- =====================================================
-- Verify only ONE row was created (idempotency worked)
-- =====================================================

select count(*) as row_count
from public.attendance_events
where dedupe_key = 'test_idempotency_key_001';

-- Expected output:
-- row_count: 1   <-- Should be exactly 1, not 2

-- =====================================================
-- TEST 2: GEOFENCE REJECTION
-- Expected: Event outside geofence gets REJECTED
-- =====================================================

select public.validate_attendance(
  jsonb_build_object(
    'user_id', '550e8400-e29b-41d4-a716-446655440000',
    'device_id', '550e8400-e29b-41d4-a716-446655440001',
    'session_id', '550e8400-e29b-41d4-a716-446655440002',
    'event_type', 'ATTEND_IN',
    'timestamp', now(),
    'location', jsonb_build_object(
      'lat', 0.0,      -- Far outside geofence (middle of ocean)
      'lng', 0.0,      -- Far outside geofence
      'accuracy', 10.0
    ),
    'biometric_ok', true,
    'biometric_timestamp', now(),
    'dedupe_key', 'test_geofence_reject_001',
    'client_event_id', '00000000-0000-0000-0000-000000000002'
  )
);

-- Expected output:
-- {
--   "status": "REJECTED",
--   "reason": "GEOFENCE_VIOLATION: Location outside geofence",
--   "event_id": "<some-uuid>",
--   "duplicate": false
-- }

-- =====================================================
-- Verify the rejected event was saved with correct status
-- =====================================================

select 
  event_type,
  status,
  server_reason,
  location_lat,
  location_lng
from public.attendance_events
where dedupe_key = 'test_geofence_reject_001';

-- Expected output:
-- event_type: ATTEND_IN
-- status: REJECTED
-- server_reason: GEOFENCE_VIOLATION: Location outside geofence
-- location_lat: 0
-- location_lng: 0

-- =====================================================
-- TEST 3: BIOMETRIC FRESHNESS REJECTION
-- Expected: Stale biometric gets REJECTED
-- =====================================================

select public.validate_attendance(
  jsonb_build_object(
    'user_id', '550e8400-e29b-41d4-a716-446655440000',
    'device_id', '550e8400-e29b-41d4-a716-446655440001',
    'session_id', '550e8400-e29b-41d4-a716-446655440002',
    'event_type', 'ATTEND_IN',
    'timestamp', now(),
    'location', jsonb_build_object(
      'lat', 6.682057,    -- REPLACE with your latitude
      'lng', 125.353906,    -- REPLACE with your longitude
      'accuracy', 10.0
    ),
    'biometric_ok', true,
    'biometric_timestamp', now() - interval '10 minutes',  -- 10 minutes old (stale)
    'dedupe_key', 'test_biometric_stale_001',
    'client_event_id', '00000000-0000-0000-0000-000000000003'
  )
);

-- Expected output:
-- {
--   "status": "REJECTED",
--   "reason": "BIOMETRIC_STALE: Biometric verification too old",
--   "event_id": "<some-uuid>",
--   "duplicate": false
-- }

-- =====================================================
-- TEST 4: SEQUENCE VALIDATION (Double sign-in)
-- Expected: Second sign-in without sign-out gets REJECTED
-- =====================================================

-- First sign-in (should succeed)
select public.validate_attendance(
  jsonb_build_object(
    'user_id', '550e8400-e29b-41d4-a716-446655440000',
    'device_id', '550e8400-e29b-41d4-a716-446655440001',
    'session_id', '550e8400-e29b-41d4-a716-446655440002',
    'event_type', 'ATTEND_IN',
    'timestamp', now(),
    'location', jsonb_build_object(
      'lat', 6.682057,    -- REPLACE with your latitude
      'lng', 125.353906,    -- REPLACE with your longitude
      'accuracy', 10.0
    ),
    'biometric_ok', true,
    'biometric_timestamp', now(),
    'dedupe_key', 'test_sequence_signin1_001',
    'client_event_id', '00000000-0000-0000-0000-000000000004'
  )
);

-- Expected: status="CONFIRMED"

-- Try to sign-in AGAIN without signing out (should be rejected)
select public.validate_attendance(
  jsonb_build_object(
    'user_id', '550e8400-e29b-41d4-a716-446655440000',
    'device_id', '550e8400-e29b-41d4-a716-446655440001',
    'session_id', '550e8400-e29b-41d4-a716-446655440002',
    'event_type', 'ATTEND_IN',  -- Second ATTEND_IN without ATTEND_OUT
    'timestamp', now(),
    'location', jsonb_build_object(
      'lat', 6.682057,    -- REPLACE with your latitude
      'lng', 125.353906,    -- REPLACE with your longitude
      'accuracy', 10.0
    ),
    'biometric_ok', true,
    'biometric_timestamp', now(),
    'dedupe_key', 'test_sequence_signin2_001',
    'client_event_id', '00000000-0000-0000-0000-000000000005'
  )
);

-- Expected output:
-- {
--   "status": "REJECTED",
--   "reason": "DUPLICATE_EVENT: Cannot perform same action twice in a row",
--   "event_id": "<some-uuid>",
--   "duplicate": false
-- }

-- =====================================================
-- TEST 5: HEARTBEAT (Minimal validation)
-- Expected: Heartbeat succeeds even without biometric
-- =====================================================

select public.record_heartbeat(
  jsonb_build_object(
    'user_id', '550e8400-e29b-41d4-a716-446655440000',
    'device_id', '550e8400-e29b-41d4-a716-446655440001',
    'session_id', '550e8400-e29b-41d4-a716-446655440002',
    'timestamp', now(),
    'location', jsonb_build_object(
      'lat', 6.682057,    -- REPLACE with your latitude
      'lng', 125.353906,    -- REPLACE with your longitude
      'accuracy', 15.0
    ),
    'dedupe_key', 'test_heartbeat_001',
    'client_event_id', '00000000-0000-0000-0000-000000000006'
  )
);

-- Expected output:
-- {
--   "status": "CONFIRMED",
--   "reason": "Heartbeat recorded successfully",
--   "event_id": "<some-uuid>",
--   "duplicate": false
-- }

-- =====================================================
-- TEST 6: ACCURACY REJECTION
-- Expected: Poor GPS accuracy gets REJECTED
-- =====================================================

select public.validate_attendance(
  jsonb_build_object(
    'user_id', '550e8400-e29b-41d4-a716-446655440000',
    'device_id', '550e8400-e29b-41d4-a716-446655440001',
    'session_id', '550e8400-e29b-41d4-a716-446655440002',
    'event_type', 'ATTEND_IN',
    'timestamp', now(),
    'location', jsonb_build_object(
      'lat', 6.682057,    -- REPLACE with your latitude
      'lng', 125.353906,    -- REPLACE with your longitude
      'accuracy', 100.0  -- Poor accuracy (> 50m threshold)
    ),
    'biometric_ok', true,
    'biometric_timestamp', now(),
    'dedupe_key', 'test_accuracy_reject_001',
    'client_event_id', '00000000-0000-0000-0000-000000000007'
  )
);

-- Expected output:
-- {
--   "status": "REJECTED",
--   "reason": "POOR_ACCURACY: Location accuracy too poor",
--   "event_id": "<some-uuid>",
--   "duplicate": false
-- }

-- =====================================================
-- SUMMARY VIEW: Check all test events
-- =====================================================

select 
  event_type,
  status,
  server_reason,
  dedupe_key,
  created_at
from public.attendance_events
where dedupe_key like 'test_%'
order by created_at desc;

-- Expected output: Should show all test events with their statuses

-- =====================================================
-- CLEANUP (Optional - run after tests to clean up)
-- =====================================================

-- Uncomment and run this to delete all test data:
-- delete from public.attendance_events where dedupe_key like 'test_%';

-- Verify cleanup:
-- select count(*) from public.attendance_events where dedupe_key like 'test_%';
-- Expected: 0
