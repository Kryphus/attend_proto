import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// Authenticates the user using biometrics ONLY (fingerprint or face recognition)
  /// Returns true if authentication is successful, false otherwise
  /// 
  /// This method:
  /// - Requires actual biometric authentication (no PIN/password fallback)
  /// - Does not store any biometric data (exam-safe)
  /// - Only returns a boolean result
  /// - Fails if device doesn't support biometrics or no biometrics are enrolled
  static Future<bool> authenticate() async {
    try {
      // Check if biometric authentication is available
      final bool isAvailable = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();

      print('DEBUG: isDeviceSupported: $isDeviceSupported');
      print('DEBUG: isAvailable: $isAvailable');

      // Device must support biometric authentication
      if (!isDeviceSupported) {
        print('DEBUG: Device does not support biometric authentication');
        return false;
      }

      // Biometrics must be enrolled and available
      if (!isAvailable) {
        print('DEBUG: No biometrics enrolled on this device');
        return false;
      }

      // Get available biometric types
      final List<BiometricType> availableBiometrics = 
          await _localAuth.getAvailableBiometrics();
      
      print('DEBUG: Available biometrics: $availableBiometrics');

      // Must have at least one biometric type available
      if (availableBiometrics.isEmpty) {
        print('DEBUG: No biometric types available');
        return false;
      }

      // Authenticate with biometrics ONLY (no PIN/password fallback)
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please use your biometric to authenticate',
        options: const AuthenticationOptions(
          biometricOnly: true, // Require biometric authentication only
          stickyAuth: true, // Keep authentication dialog open if user cancels
        ),
      );

      print('DEBUG: Authentication result: $didAuthenticate');
      return didAuthenticate;
    } catch (e) {
      // Handle any errors during authentication
      print('DEBUG: Authentication error: $e');
      return false;
    }
  }

  /// Check if biometric authentication is available on the device
  static Future<bool> isBiometricAvailable() async {
    try {
      final bool isAvailable = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  /// Get the list of available biometric types on the device
  static Future<List<BiometricType>> getAvailableBiometricTypes() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Check if the device supports biometric authentication
  static Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }
}

