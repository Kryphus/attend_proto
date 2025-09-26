import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapFencePage extends StatefulWidget {
  const MapFencePage({super.key});

  @override
  State<MapFencePage> createState() => _MapFencePageState();
}

class _MapFencePageState extends State<MapFencePage> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  LatLng? _fenceCenter;
  double _fenceRadius = 100.0; // Default radius in meters
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationError('Location services are disabled. Please enable them.');
        return;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Location permissions are denied.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationError('Location permissions are permanently denied.');
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      // Center camera on current location
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(_currentLocation!),
        );
      }
    } catch (e) {
      _showLocationError('Error getting location: $e');
    }
  }

  void _showLocationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _onMapLongPress(LatLng position) {
    setState(() {
      _fenceCenter = position;
      _markers = {
        Marker(
          markerId: const MarkerId('fence_center'),
          position: position,
          infoWindow: const InfoWindow(
            title: 'Fence Center',
            snippet: 'Long press to move',
          ),
        ),
      };
      _updateCircle();
    });
  }

  void _updateCircle() {
    if (_fenceCenter != null) {
      setState(() {
        _circles = {
          Circle(
            circleId: const CircleId('fence_circle'),
            center: _fenceCenter!,
            radius: _fenceRadius,
            fillColor: Colors.blue.withOpacity(0.2),
            strokeColor: Colors.blue,
            strokeWidth: 2,
          ),
        };
      });
    }
  }

  void _onRadiusChanged(double value) {
    setState(() {
      _fenceRadius = value;
    });
    _updateCircle();
  }

  void _useThisFence() {
    if (_fenceCenter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set a fence center by long-pressing on the map'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Return the fence data to the previous screen
    Navigator.pop(context, {
      'centerLat': _fenceCenter!.latitude,
      'centerLng': _fenceCenter!.longitude,
      'radius': _fenceRadius,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Geofence'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 3,
            child: _currentLocation == null
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : GoogleMap(
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                      if (_currentLocation != null) {
                        controller.animateCamera(
                          CameraUpdate.newLatLng(_currentLocation!),
                        );
                      }
                    },
                    initialCameraPosition: CameraPosition(
                      target: _currentLocation ?? const LatLng(37.7749, -122.4194),
                      zoom: 15.0,
                    ),
                    onLongPress: _onMapLongPress,
                    markers: _markers,
                    circles: _circles,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                  ),
          ),
          
          // Controls
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Instructions
                  Text(
                    'Long press on the map to set fence center',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  
                  // Radius slider
                  Row(
                    children: [
                      const Icon(Icons.radio_button_unchecked, size: 20),
                      Expanded(
                        child: Slider(
                          value: _fenceRadius,
                          min: 50.0,
                          max: 250.0,
                          divisions: 20,
                          label: '${_fenceRadius.round()}m',
                          onChanged: _onRadiusChanged,
                        ),
                      ),
                      const Icon(Icons.radio_button_checked, size: 20),
                    ],
                  ),
                  
                  // Use fence button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _useThisFence,
                      icon: const Icon(Icons.check),
                      label: const Text('Use This Fence'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

