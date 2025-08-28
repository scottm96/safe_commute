import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationService with ChangeNotifier {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isTracking = false;
  String? _errorMessage;
  Timer? _retryTimer;
  int _retryAttempts = 0;
  static const int maxRetryAttempts = 3;

  Position? get currentPosition => _currentPosition;
  bool get isTracking => _isTracking;
  String? get errorMessage => _errorMessage;

  // Start location tracking with improved error handling and retry logic
  Future<bool> startLocationTracking({
    Function(Position)? onLocationUpdate,
  }) async {
    if (_isTracking) return true;

    debugPrint("Starting location tracking...");

    try {
      // Check permissions with detailed feedback
      LocationPermission permission = await _checkAndRequestPermissions();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        _setError('Location permissions denied. Please enable in settings.');
        return false;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setError('Location services disabled. Please enable GPS.');
        // Try to open location settings
        bool opened = await Geolocator.openLocationSettings();
        if (!opened) {
          _setError('Please enable GPS in device settings');
          return false;
        }
        
        // Wait a moment and check again
        await Future.delayed(const Duration(seconds: 2));
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          _setError('GPS still disabled. Please enable location services.');
          return false;
        }
      }

      _isTracking = true;
      _retryAttempts = 0;
      _clearError();

      // Get initial position with timeout
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
        debugPrint("Initial position obtained: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}");
      } catch (e) {
        debugPrint('Error getting initial position: $e');
        // Try with lower accuracy
        try {
          _currentPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
          debugPrint("Initial position obtained with medium accuracy");
        } catch (e2) {
          debugPrint('Failed to get initial position with medium accuracy: $e2');
        }
      }

      // Start position stream with appropriate settings
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
        timeLimit: Duration(seconds: 30),
      );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _currentPosition = position;
          _retryAttempts = 0; // Reset retry attempts on success
          _clearError();
          onLocationUpdate?.call(position);
          notifyListeners();
          debugPrint("Location updated: ${position.latitude}, ${position.longitude}, speed: ${position.speed}");
        },
        onError: (error) {
          _setError('Location tracking error: $error');
          debugPrint('Position stream error: $error');
          
          // Implement retry logic
          if (_retryAttempts < maxRetryAttempts) {
            _retryAttempts++;
            debugPrint('Retrying location tracking (attempt $_retryAttempts)');
            _retryTimer = Timer(Duration(seconds: 5 * _retryAttempts), () {
              if (_isTracking) {
                startLocationTracking(onLocationUpdate: onLocationUpdate);
              }
            });
          }
        },
        onDone: () {
          debugPrint('Position stream completed');
        },
      );

      notifyListeners();
      return true;

    } catch (e) {
      _setError('Failed to start location tracking: $e');
      _isTracking = false;
      notifyListeners();
      debugPrint('Location service error: $e');
      return false;
    }
  }

  // Stop location tracking
  void stopLocationTracking() {
    debugPrint("Stopping location tracking");
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _isTracking = false;
    _retryAttempts = 0;
    _currentPosition = null;
    _clearError();
    notifyListeners();
  }

  // Enhanced permission checking with detailed status
  Future<LocationPermission> _checkAndRequestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    debugPrint("Current location permission: $permission");
    
    if (permission == LocationPermission.denied) {
      debugPrint("Requesting location permission");
      permission = await Geolocator.requestPermission();
      debugPrint("Permission after request: $permission");
    }

    return permission;
  }

  // Get current location once with better error handling
  Future<Position?> getCurrentLocation() async {
    try {
      LocationPermission permission = await _checkAndRequestPermissions();
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        _setError('Location permissions not granted');
        return null;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setError('Location services are disabled');
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      _currentPosition = position;
      _clearError();
      notifyListeners();
      return position;

    } catch (e) {
      // Try with lower accuracy if high accuracy fails
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
        
        _currentPosition = position;
        _clearError();
        notifyListeners();
        return position;
      } catch (e2) {
        _setError('Failed to get location: $e2');
        debugPrint('Location error: $e2');
        return null;
      }
    }
  }

  // Calculate distance between two points
  double getDistanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  // Calculate bearing between two points
  double getBearingBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    return Geolocator.bearingBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }

  // Check if location permissions are permanently denied
  Future<bool> isLocationPermissionDeniedForever() async {
    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.deniedForever;
  }

  // Open app settings for location permissions
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  void _setError(String error) {
    _errorMessage = error;
    debugPrint("Location service error: $error");
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopLocationTracking();
    super.dispose();
  }
}