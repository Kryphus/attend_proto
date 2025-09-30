import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logging_service.dart';

/// Supabase configuration and initialization
class SupabaseConfig {
  static const String _component = 'SupabaseConfig';
  
  // TODO: Replace these with your actual Supabase credentials
  static const String supabaseUrl = 'https://bdltoqempkpotiirrblm.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJkbHRvcWVtcGtwb3RpaXJyYmxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkwNDUwOTgsImV4cCI6MjA3NDYyMTA5OH0.-URgPLbh7MSUXX_UYhUY18vkR20LQUcLbnOJsitdRuc';
  
  /// Initialize Supabase
  static Future<void> initialize() async {
    try {
      // Skip initialization if credentials are not set
      if (supabaseUrl == 'YOUR_SUPABASE_URL_HERE' || 
          supabaseAnonKey == 'YOUR_SUPABASE_ANON_KEY_HERE') {
        logger.warn(
          'Supabase credentials not configured - sync will be disabled',
          _component,
          {
            'url_configured': supabaseUrl != 'YOUR_SUPABASE_URL_HERE',
            'key_configured': supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY_HERE',
          },
        );
        return;
      }

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        debug: false, // Set to true for debugging
      );

      logger.info(
        'Supabase initialized successfully',
        _component,
        {
          'url': supabaseUrl,
          'client_initialized': Supabase.instance.client != null,
        },
      );

    } catch (e) {
      logger.error(
        'Failed to initialize Supabase',
        _component,
        {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Get Supabase client instance
  static SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (e) {
      logger.error(
        'Failed to get Supabase client',
        _component,
        {'error': e.toString()},
      );
      return null;
    }
  }

  /// Check if Supabase is properly configured
  static bool get isConfigured {
    return supabaseUrl != 'YOUR_SUPABASE_URL_HERE' && 
           supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY_HERE';
  }
}
