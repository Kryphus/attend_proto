# Feature Flags & Environment Configuration (O0)

This document describes the Feature Flags system implemented for the attendance app's offline mode architecture.

## Overview

The Feature Flags system provides environment-based configuration with a clear precedence hierarchy:

1. **--dart-define command line arguments** (highest priority)
2. **.env file values** (medium priority)  
3. **Default values based on environment** (lowest priority)

## Configuration Values

| Flag | Dev Default | Prod Default | Description |
|------|-------------|--------------|-------------|
| `heartbeatInterval` | 1 minute | 1 hour | How often to check location/presence |
| `syncInterval` | 1 minute | 1 hour | How often to sync with server |
| `biometricFreshness` | 5 minutes | 5 minutes | How long biometric auth is valid |
| `geofenceRadiusMeters` | 100m | 100m | Geofence radius in meters |
| `maxRetryBackoff` | 10 minutes | 2 hours | Maximum retry backoff duration |

## Usage Examples

### 1. Default Development Mode
```bash
flutter run
# Uses dev defaults: 1-minute intervals for fast testing
```

### 2. Production Mode via dart-define
```bash
flutter run --dart-define=ENVIRONMENT=prod
# Uses prod defaults: 1-hour intervals
```

### 3. Custom Values via dart-define
```bash
flutter run --dart-define=HEARTBEAT_INTERVAL_MINUTES=5 --dart-define=SYNC_INTERVAL_MINUTES=10
# Uses custom 5-minute heartbeat, 10-minute sync
```

### 4. Using .env File
Create a `.env` file in the project root:
```env
ENVIRONMENT=dev
HEARTBEAT_INTERVAL_MINUTES=2
SYNC_INTERVAL_MINUTES=3
GEOFENCE_RADIUS_METERS=150
```

Then run:
```bash
flutter run
# Uses .env values where specified, defaults for others
```

## Testing

### Unit Tests
```bash
flutter test test/config/feature_flags_test.dart
```

### Manual Testing

1. **Test Dev Mode (default)**:
   ```bash
   flutter run
   ```
   Expected console output:
   ```
   🚩 Feature Flags Configuration:
      Environment: dev
      Heartbeat Interval: 0:01:00.000000
      Sync Interval: 0:01:00.000000
      ...
   ```

2. **Test Prod Mode**:
   ```bash
   flutter run --dart-define=ENVIRONMENT=prod
   ```
   Expected console output:
   ```
   🚩 Feature Flags Configuration:
      Environment: prod
      Heartbeat Interval: 1:00:00.000000
      Sync Interval: 1:00:00.000000
      ...
   ```

3. **Test Custom Values**:
   ```bash
   flutter run --dart-define=HEARTBEAT_INTERVAL_MINUTES=5
   ```
   Expected console output:
   ```
   🚩 Feature Flags Configuration:
      Environment: dev
      Heartbeat Interval: 0:05:00.000000
      ...
   ```

## Implementation Details

### Files Created/Modified

- **NEW**: `lib/config/feature_flags.dart` - Main feature flags implementation
- **NEW**: `test/config/feature_flags_test.dart` - Unit tests
- **NEW**: `env.example` - Example .env file
- **UPDATED**: `lib/main.dart` - Initialize flags and use in foreground task
- **UPDATED**: `pubspec.yaml` - Added flutter_dotenv dependency

### Key Features

1. **Environment Detection**: Automatically detects dev vs prod mode
2. **Precedence System**: dart-define > .env > defaults
3. **Graceful Fallbacks**: Invalid values fall back to environment defaults
4. **Logging**: Comprehensive logging of active configuration
5. **UI Integration**: Feature flags displayed in tracking logs

### Code Integration

The feature flags are integrated into:
- **Foreground Task**: Uses `FeatureFlags.heartbeatInterval` for repeat events
- **UI Simulator**: Uses `FeatureFlags.heartbeatInterval` for periodic updates
- **Logging**: Shows current configuration in tracking logs

## Next Steps

This completes **O0 - Env Flags & Timing**. The system is ready for:
- Fast development testing (1-minute cycles)
- Production deployment (1-hour cycles)
- Easy switching between modes without code changes

The next phase (O1) can now build upon this foundation for the offline mode event log and outbox implementation.
