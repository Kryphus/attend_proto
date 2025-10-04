# 🚀 Quick Start Guide - TagMeIn+ Offline Mode

## For the Impatient Developer

Want to see the offline mode in action **right now**? Follow this 5-minute quickstart.

---

## ⚡ Prerequisites (2 minutes)

### 1. **Verify Supabase is Running**

Go to your Supabase project dashboard: https://supabase.com/dashboard

- ✅ Project is active
- ✅ Tables exist: `users`, `devices`, `sessions`, `attendance_events`

### 2. **Update Session Coordinates**

Open Supabase SQL Editor and run:

```sql
-- Check current session location
SELECT 
  name,
  ST_Y(geofence_center::geometry) as lat,
  ST_X(geofence_center::geometry) as lng,
  geofence_radius_m
FROM public.sessions 
WHERE id = '550e8400-e29b-41d4-a716-446655440002';
```

**If coordinates don't match your location, update:**

```sql
UPDATE public.sessions
SET 
  geofence_center = ST_SetSRID(ST_MakePoint(<YOUR_LONGITUDE>, <YOUR_LATITUDE>), 4326)::geography,
  geofence_radius_m = 500,  -- 500 meters radius
  starts_at = now() - interval '1 hour',
  ends_at = now() + interval '8 hours'
WHERE id = '550e8400-e29b-41d4-a716-446655440002';
```

**Pro tip:** Use Google Maps to get your coordinates:
1. Right-click your location on Google Maps
2. Click the coordinates (e.g., "14.5995, 120.9842")
3. First number = latitude, second = longitude

---

## 🎬 3-Minute Demo

### **Test 1: Online Check-In (30 seconds)**

```powershell
# 1. Launch app
flutter run

# 2. In the app:
#    - Tap "Check In"
#    - Authenticate with fingerprint
#    - Watch status: PENDING → CONFIRMED (≤30s)
```

**Expected:** Green "CONFIRMED" pill appears

---

### **Test 2: Offline Mode (2 minutes)**

```powershell
# 1. Enable Airplane Mode on your device
#    - Offline banner appears at top

# 2. Tap "Check Out"
#    - Authenticate
#    - Status: PENDING (yellow)
#    - Banner: "You're offline"

# 3. Try "Sync Now"
#    - Shows error (expected!)
#    - Event stays PENDING

# 4. Disable Airplane Mode
#    - Offline banner disappears
#    - Auto-sync triggers
#    - Status: PENDING → CONFIRMED
```

**Expected:** Event syncs after network restored

---

### **Test 3: Dev Profile (30 seconds)**

```powershell
# 1. Tap purple developer icon (top-right)

# 2. View metrics:
#    - capture.success: 2
#    - event.confirmed: 2
#    - sync.success: 2+

# 3. Tap "Dump Logs"
#    - Logs copied to clipboard
#    - Paste to see JSON

# 4. Done!
```

---

## ✅ Verification Checklist

After the 3-minute demo:

- [ ] Check-in went PENDING → CONFIRMED
- [ ] Offline banner appeared in airplane mode
- [ ] Offline check-out captured locally
- [ ] Auto-sync triggered after network restored
- [ ] Dev Profile showed metrics

**If all checked:** 🎉 **Offline mode is working!**

---

## 🔧 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| Events stuck PENDING | Tap "Sync Now" or check network |
| All events REJECTED | Update geofence coordinates to your location |
| No offline banner | Check if airplane mode actually disabled network |
| App crashes on check-in | Verify biometric is set up on device |
| Sync never happens | Check `FeatureFlags.enableOfflineMode` is true |

---

## 📚 Next Steps

Want to learn more?

- 📖 **Full Demo:** See `E2E_DEMO_SCRIPT.md` for 8 detailed scenarios
- 🧪 **Run Tests:** `flutter test` to verify all 100+ tests pass
- 🔍 **Deep Dive:** Read `O1_COMPLETE_SUMMARY.md` through `O8_COMPLETE_SUMMARY.md`

---

## 🎯 Pro Tips

1. **Always check geofence first** - 90% of issues are location-related
2. **Use Dev Profile** - It's your best debugging tool
3. **Dump logs** - When something's wrong, check the logs
4. **Reset metrics** - Start fresh for clean demos
5. **Airplane mode = true offline** - Wi-Fi off isn't enough on some devices

---

## 🚀 You're Ready!

That's it! You now know how to demo the offline mode system.

**Want the full experience?** See `E2E_DEMO_SCRIPT.md` for all 8 scenarios.

**Ready to present?** You've got a production-ready offline-first system! 🎉

