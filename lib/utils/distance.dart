import 'package:geolocator/geolocator.dart';

class DistanceUtils {
  /// Checks if a given point (lat, lng) is inside a circular geofence
  /// 
  /// Parameters:
  /// - lat: Latitude of the point to check
  /// - lng: Longitude of the point to check
  /// - centerLat: Latitude of the geofence center
  /// - centerLng: Longitude of the geofence center
  /// - radiusMeters: Radius of the geofence in meters
  /// 
  /// Returns:
  /// - true if the point is inside the geofence
  /// - false if the point is outside the geofence or if there's an error
  static bool isInside({
    required double lat,
    required double lng,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) {
    try {
      // Validate input parameters
      if (!_isValidCoordinate(lat) || !_isValidCoordinate(lng) ||
          !_isValidCoordinate(centerLat) || !_isValidCoordinate(centerLng)) {
        return false;
      }

      if (radiusMeters < 0) {
        return false;
      }

      // Calculate distance between the point and the geofence center
      double distanceInMeters = Geolocator.distanceBetween(
        centerLat,
        centerLng,
        lat,
        lng,
      );

      // Check if the distance is within the radius
      return distanceInMeters <= radiusMeters;
    } catch (e) {
      // Return false on any error (invalid coordinates, calculation error, etc.)
      return false;
    }
  }

  /// Validates if a coordinate is within valid latitude/longitude ranges
  /// 
  /// Parameters:
  /// - coordinate: The coordinate value to validate
  /// 
  /// Returns:
  /// - true if the coordinate is valid
  /// - false if the coordinate is invalid
  static bool _isValidCoordinate(double coordinate) {
    // Check for NaN or infinite values
    if (coordinate.isNaN || coordinate.isInfinite) {
      return false;
    }

    // For latitude: valid range is -90 to 90
    // For longitude: valid range is -180 to 180
    // We'll use a more restrictive range to be safe
    return coordinate >= -180 && coordinate <= 180;
  }

  /// Calculates the distance between two points in meters
  /// 
  /// Parameters:
  /// - lat1, lng1: First point coordinates
  /// - lat2, lng2: Second point coordinates
  /// 
  /// Returns:
  /// - Distance in meters, or -1 if there's an error
  static double getDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    try {
      // Validate input parameters
      if (!_isValidCoordinate(lat1) || !_isValidCoordinate(lng1) ||
          !_isValidCoordinate(lat2) || !_isValidCoordinate(lng2)) {
        return -1;
      }

      return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    } catch (e) {
      return -1;
    }
  }

  /// Checks if a point is inside a geofence with additional validation
  /// 
  /// This is an alternative method that provides more detailed error information
  /// 
  /// Parameters:
  /// - lat: Latitude of the point to check
  /// - lng: Longitude of the point to check
  /// - centerLat: Latitude of the geofence center
  /// - centerLng: Longitude of the geofence center
  /// - radiusMeters: Radius of the geofence in meters
  /// 
  /// Returns:
  /// - Map with 'isInside' boolean and 'distance' in meters
  /// - Returns null if there's an error
  static Map<String, dynamic>? isInsideWithDistance({
    required double lat,
    required double lng,
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
  }) {
    try {
      // Validate input parameters
      if (!_isValidCoordinate(lat) || !_isValidCoordinate(lng) ||
          !_isValidCoordinate(centerLat) || !_isValidCoordinate(centerLng)) {
        return null;
      }

      if (radiusMeters < 0) {
        return null;
      }

      // Calculate distance between the point and the geofence center
      double distanceInMeters = Geolocator.distanceBetween(
        centerLat,
        centerLng,
        lat,
        lng,
      );

      return {
        'isInside': distanceInMeters <= radiusMeters,
        'distance': distanceInMeters,
      };
    } catch (e) {
      return null;
    }
  }
}

