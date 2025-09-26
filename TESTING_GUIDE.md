# Attendance App Testing Guide

## Overview
This guide covers how to test the attendance tracking app, including manual testing, automated testing, and troubleshooting common issues.

## Prerequisites

### Device Requirements
- **Physical Android device** (biometric authentication doesn't work well on emulators)
- Android 6.0+ (API level 23+)
- Location services enabled
- Biometric authentication set up (fingerprint, face unlock, or PIN)

### Development Setup
- Flutter SDK installed
- Android Studio or VS Code with Flutter extensions
- Device connected via USB with USB debugging enabled

## Testing Methods

### 1. Automated Unit Tests

Run the existing test suite:
```bash
flutter test
```

**What the tests cover:**
- App loads correctly
- UI elements are present
- Error handling for missing geofence
- Basic widget functionality

### 2. Manual Testing on Device

#### Step 1: Build and Install
```bash
# For development testing
flutter run --debug

# For production-like testing
flutter run --release
```

#### Step 2: Test Geofence Setup
1. Launch the app
2. Tap "Set Geofence"
3. Select a location on the map
4. Set a reasonable radius (50-100 meters)
5. Verify coordinates are displayed on the main screen

#### Step 3: Test Check-in Process
1. **Location Test:**
   - Stand outside the geofence → Should show "outside fence" error
   - Move inside the geofence → Should proceed to authentication

2. **Authentication Test:**
   - Tap "Check In" while inside geofence
   - Complete biometric authentication when prompted
   - Verify "Presence tracking started" message appears

3. **Tracking Test:**
   - Verify status shows "Tracking started - Inside fence"
   - Move outside geofence (should continue tracking)
   - Tap "Stop Tracking" to end session

## Troubleshooting

### Authentication Issues

#### Problem: "Authentication failed. Check in cancelled"

**Common Causes:**
1. **No biometric setup on device**
   - Go to Settings > Security > Biometric & Security
   - Set up fingerprint, face unlock, or PIN

2. **Missing permissions**
   - Check if app has biometric permissions
   - Reinstall app after adding permissions to manifest

3. **Device compatibility**
   - Some older devices may not support biometric authentication
   - Check device specifications

**Debug Steps:**
1. Run the app with debug output:
   ```bash
   flutter run --debug
   ```
2. Check console output for debug messages:
   - `DEBUG: isDeviceSupported: true/false`
   - `DEBUG: isAvailable: true/false`
   - `DEBUG: Available biometrics: [...]`
   - `DEBUG: Authentication result: true/false`

3. If `isDeviceSupported: false`, your device doesn't support biometric auth
4. If `isAvailable: false`, you need to set up biometrics in device settings

### Location Issues

#### Problem: "Location services are disabled"
- Enable location services in device settings
- Grant location permissions to the app

#### Problem: "You are outside the fence"
- Check your actual location vs. the geofence center
- Increase geofence radius if needed
- Ensure GPS accuracy is good

### Permission Issues

#### Required Permissions:
- `ACCESS_FINE_LOCATION` - For precise location
- `ACCESS_COARSE_LOCATION` - For approximate location
- `ACCESS_BACKGROUND_LOCATION` - For background tracking
- `USE_BIOMETRIC` - For biometric authentication
- `USE_FINGERPRINT` - For fingerprint authentication
- `POST_NOTIFICATIONS` - For notifications

#### Granting Permissions:
1. Go to device Settings > Apps > Attendance Tracker > Permissions
2. Enable all required permissions
3. Restart the app

## Testing Scenarios

### Scenario 1: Complete Workflow
1. Set up geofence at your current location
2. Check in successfully
3. Move around within the fence
4. Move outside the fence
5. Stop tracking

### Scenario 2: Error Handling
1. Try to check in without setting geofence
2. Try to check in while outside the fence
3. Try to check in with location services disabled
4. Try to check in without biometric setup

### Scenario 3: Edge Cases
1. Very small geofence (5-10 meters)
2. Very large geofence (500+ meters)
3. Poor GPS signal areas
4. App backgrounding during tracking

## Performance Testing

### Battery Usage
- Monitor battery consumption during tracking
- Test with different tracking intervals
- Check background task efficiency

### Location Accuracy
- Test in different environments (indoor/outdoor)
- Verify fence boundary detection
- Test with different GPS accuracy levels

## Security Testing

### Biometric Authentication
- Test with different biometric types
- Verify fallback to PIN/password works
- Test authentication cancellation

### Data Privacy
- Verify no biometric data is stored
- Check location data handling
- Test app data clearing

## Reporting Issues

When reporting issues, include:
1. Device model and Android version
2. Steps to reproduce
3. Expected vs. actual behavior
4. Debug console output
5. Screenshots if applicable

## Continuous Testing

### Before Each Release
1. Run unit tests: `flutter test`
2. Test on multiple devices
3. Test different Android versions
4. Verify all permissions work
5. Test biometric authentication
6. Test location accuracy

### Automated Testing Setup
Consider setting up:
- CI/CD pipeline with automated tests
- Device farm testing
- Performance monitoring
- Crash reporting integration
