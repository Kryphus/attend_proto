import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/logging_service.dart';

/// Service for monitoring network connectivity changes
class ConnectivityService {
  static const String _component = 'ConnectivityService';
  
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  bool _isConnected = false;
  bool _wasConnected = false;
  
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  final StreamController<void> _reconnectionController = StreamController<void>.broadcast();

  /// Stream of connectivity status changes
  Stream<bool> get connectivityStream => _connectivityController.stream;
  
  /// Stream that fires when connectivity is regained after being lost
  Stream<void> get reconnectionStream => _reconnectionController.stream;
  
  /// Current connectivity status
  bool get isConnected => _isConnected;

  /// Initialize connectivity monitoring
  Future<void> initialize() async {
    try {
      // Check initial connectivity
      final result = await _connectivity.checkConnectivity();
      final hasNetworkInterface = _hasInternetConnection(result);
      
      // Test actual internet connectivity if we have a network interface
      _isConnected = hasNetworkInterface ? await _testInternetConnectivity() : false;
      _wasConnected = _isConnected;
      
      logger.info(
        'Connectivity service initialized',
        _component,
        {
          'initial_connectivity': result.map((r) => r.name).toList(),
          'network_interface': hasNetworkInterface,
          'internet_test': _isConnected,
          'is_connected': _isConnected,
        },
      );

      // Listen for connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _onConnectivityChanged,
        onError: (error) {
          logger.error(
            'Connectivity stream error',
            _component,
            {'error': error.toString()},
          );
        },
      );
      
    } catch (e) {
      logger.error(
        'Failed to initialize connectivity service',
        _component,
        {'error': e.toString()},
      );
    }
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final wasConnected = _isConnected;
    final hasNetworkInterface = _hasInternetConnection(results);
    
    // If we have a network interface, test actual internet connectivity
    if (hasNetworkInterface) {
      _isConnected = await _testInternetConnectivity();
    } else {
      _isConnected = false;
    }
    
    logger.info(
      'Connectivity changed',
      _component,
      {
        'previous_state': wasConnected,
        'current_state': _isConnected,
        'network_interface': hasNetworkInterface,
        'internet_test': _isConnected,
        'connectivity_types': results.map((r) => r.name).toList(),
      },
    );

    // Emit connectivity status change
    _connectivityController.add(_isConnected);

    // Emit reconnection event if we regained connectivity
    if (!wasConnected && _isConnected) {
      logger.info(
        'Network connectivity regained',
        _component,
        {'trigger_sync': true},
      );
      _reconnectionController.add(null);
    }

    _wasConnected = _isConnected;
  }

  /// Check if any of the connectivity results indicate internet access
  bool _hasInternetConnection(List<ConnectivityResult> results) {
    return results.any((result) => 
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.mobile ||
      result == ConnectivityResult.ethernet
    );
  }

  /// Test actual internet connectivity by pinging a reliable server
  Future<bool> _testInternetConnectivity() async {
    try {
      // Try to connect to Google's DNS server (reliable and fast)
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        logger.debug(
          'Internet connectivity test passed',
          _component,
          {'dns_lookup': 'google.com', 'result': 'success'},
        );
        return true;
      }
    } catch (e) {
      logger.debug(
        'Internet connectivity test failed',
        _component,
        {'dns_lookup': 'google.com', 'error': e.toString()},
      );
    }
    return false;
  }

  /// Manually check current connectivity (useful for sync operations)
  Future<bool> checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final hasNetworkInterface = _hasInternetConnection(result);
      
      // If we have a network interface, test actual internet connectivity
      final actuallyConnected = hasNetworkInterface ? await _testInternetConnectivity() : false;
      
      logger.debug(
        'Manual connectivity check',
        _component,
        {
          'connectivity_types': result.map((r) => r.name).toList(),
          'network_interface': hasNetworkInterface,
          'internet_test': actuallyConnected,
          'is_connected': actuallyConnected,
        },
      );
      
      return actuallyConnected;
    } catch (e) {
      logger.error(
        'Failed to check connectivity',
        _component,
        {'error': e.toString()},
      );
      return false;
    }
  }

  /// Get connectivity status description for UI
  String getConnectivityDescription() {
    if (!_isConnected) {
      return 'Offline';
    }
    
    // For more detailed status, we'd need to check the actual connection type
    return 'Online';
  }

  /// Dispose of resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityController.close();
    _reconnectionController.close();
    
    logger.debug(
      'Connectivity service disposed',
      _component,
      {},
    );
  }
}
