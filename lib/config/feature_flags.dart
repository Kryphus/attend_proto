import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Feature flags and configuration values for the attendance app.
/// 
/// Supports environment-based configuration with precedence:
/// 1. --dart-define command line arguments (highest priority)
/// 2. .env file values
/// 3. Default values based on environment (lowest priority)
class FeatureFlags {
  static const String _envDev = 'dev';
  static const String _envProd = 'prod';
  
  static bool _initialized = false;
  static bool _dotenvLoaded = false;
  
  /// Initialize the feature flags system (loads .env file if available)
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      await dotenv.load(fileName: ".env");
      _dotenvLoaded = true;
    } catch (e) {
      // .env file not found or couldn't be loaded - this is fine
      // We'll fall back to dart-define and defaults
      _dotenvLoaded = false;
    }
    
    _initialized = true;
  }
  
  /// Get a value from .env file with fallback to default
  static String _getEnvValue(String envKey, String defaultValue) {
    // Check .env file (only if initialized and dotenv is loaded)
    if (_initialized && _dotenvLoaded) {
      try {
        if (dotenv.env.containsKey(envKey)) {
          final envValue = dotenv.env[envKey];
          if (envValue != null && envValue.isNotEmpty) {
            return envValue;
          }
        }
      } catch (e) {
        // dotenv not properly loaded, fall back to default
      }
    }
    
    // Return default
    return defaultValue;
  }
  
  // Environment detection
  static String get environment {
    // 1. Check dart-define (highest priority)
    const dartDefineValue = String.fromEnvironment('ENVIRONMENT', defaultValue: '');
    if (dartDefineValue.isNotEmpty) {
      return dartDefineValue;
    }
    
    // 2. Check .env file, fallback to dev default
    return _getEnvValue('ENVIRONMENT', _envDev);
  }
  
  static bool get isDev => environment == _envDev;
  static bool get isProd => environment == _envProd;
  
  // Heartbeat interval - how often to check location/presence
  static Duration get heartbeatInterval {
    // 1. Check dart-define (highest priority)
    const dartDefineValue = String.fromEnvironment('HEARTBEAT_INTERVAL_MINUTES', defaultValue: '');
    if (dartDefineValue.isNotEmpty) {
      final minutes = int.tryParse(dartDefineValue);
      if (minutes != null) {
        return Duration(minutes: minutes);
      }
    }
    
    // 2. Check .env file
    final envValue = _getEnvValue('HEARTBEAT_INTERVAL_MINUTES', '');
    if (envValue.isNotEmpty) {
      final minutes = int.tryParse(envValue);
      if (minutes != null) {
        return Duration(minutes: minutes);
      }
    }
    
    // 3. Default values based on environment
    return isDev 
        ? const Duration(minutes: 1)   // Dev: 1 minute for fast testing
        : const Duration(hours: 1);    // Prod: 1 hour
  }
  
  // Sync interval - how often to sync with server
  static Duration get syncInterval {
    // 1. Check dart-define (highest priority)
    const dartDefineValue = String.fromEnvironment('SYNC_INTERVAL_MINUTES', defaultValue: '');
    if (dartDefineValue.isNotEmpty) {
      final minutes = int.tryParse(dartDefineValue);
      if (minutes != null) {
        return Duration(minutes: minutes);
      }
    }
    
    // 2. Check .env file
    final envValue = _getEnvValue('SYNC_INTERVAL_MINUTES', '');
    if (envValue.isNotEmpty) {
      final minutes = int.tryParse(envValue);
      if (minutes != null) {
        return Duration(minutes: minutes);
      }
    }
    
    // 3. Default values based on environment
    return isDev 
        ? const Duration(minutes: 1)   // Dev: 1 minute for fast testing
        : const Duration(hours: 1);    // Prod: 1 hour
  }
  
  // Biometric freshness - how long biometric auth is valid
  static Duration get biometricFreshness {
    // 1. Check dart-define (highest priority)
    const dartDefineValue = String.fromEnvironment('BIOMETRIC_FRESHNESS_MINUTES', defaultValue: '');
    if (dartDefineValue.isNotEmpty) {
      final minutes = int.tryParse(dartDefineValue);
      if (minutes != null) {
        return Duration(minutes: minutes);
      }
    }
    
    // 2. Check .env file
    final envValue = _getEnvValue('BIOMETRIC_FRESHNESS_MINUTES', '');
    if (envValue.isNotEmpty) {
      final minutes = int.tryParse(envValue);
      if (minutes != null) {
        return Duration(minutes: minutes);
      }
    }
    
    // 3. Default: 5 minutes for both dev and prod
    return const Duration(minutes: 5);
  }
  
  // Geofence radius in meters
  static double get geofenceRadiusMeters {
    // 1. Check dart-define (highest priority)
    const dartDefineValue = String.fromEnvironment('GEOFENCE_RADIUS_METERS', defaultValue: '');
    if (dartDefineValue.isNotEmpty) {
      final radius = double.tryParse(dartDefineValue);
      if (radius != null) {
        return radius;
      }
    }
    
    // 2. Check .env file
    final envValue = _getEnvValue('GEOFENCE_RADIUS_METERS', '');
    if (envValue.isNotEmpty) {
      final radius = double.tryParse(envValue);
      if (radius != null) {
        return radius;
      }
    }
    
    // 3. Default: 100 meters for both dev and prod
    return 100.0;
  }
  
  // Maximum retry backoff duration
  static Duration get maxRetryBackoff {
    // 1. Check dart-define (highest priority)
    const dartDefineValue = String.fromEnvironment('MAX_RETRY_BACKOFF_MINUTES', defaultValue: '');
    if (dartDefineValue.isNotEmpty) {
      final minutes = int.tryParse(dartDefineValue);
      if (minutes != null) {
        return Duration(minutes: minutes);
      }
    }
    
    // 2. Check .env file
    final envValue = _getEnvValue('MAX_RETRY_BACKOFF_MINUTES', '');
    if (envValue.isNotEmpty) {
      final minutes = int.tryParse(envValue);
      if (minutes != null) {
        return Duration(minutes: minutes);
      }
    }
    
    // 3. Default values based on environment
    return isDev 
        ? const Duration(minutes: 10)  // Dev: 10 minutes
        : const Duration(hours: 2);    // Prod: 2 hours
  }
  
  /// Get a summary of all current feature flag values
  static Map<String, dynamic> getAllFlags() {
    return {
      'environment': environment,
      'heartbeatInterval': heartbeatInterval.toString(),
      'syncInterval': syncInterval.toString(),
      'biometricFreshness': biometricFreshness.toString(),
      'geofenceRadiusMeters': geofenceRadiusMeters,
      'maxRetryBackoff': maxRetryBackoff.toString(),
    };
  }
  
  /// Get a formatted string for logging
  static String getLogString() {
    final flags = getAllFlags();
    final buffer = StringBuffer();
    buffer.writeln('🚩 Feature Flags Configuration:');
    buffer.writeln('   Environment: ${flags['environment']}');
    buffer.writeln('   Heartbeat Interval: ${flags['heartbeatInterval']}');
    buffer.writeln('   Sync Interval: ${flags['syncInterval']}');
    buffer.writeln('   Biometric Freshness: ${flags['biometricFreshness']}');
    buffer.writeln('   Geofence Radius: ${flags['geofenceRadiusMeters']}m');
    buffer.writeln('   Max Retry Backoff: ${flags['maxRetryBackoff']}');
    return buffer.toString();
  }
}
