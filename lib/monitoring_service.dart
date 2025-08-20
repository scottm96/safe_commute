import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

enum DriverAlertLevel { none, mild, moderate, severe }

class DriverStatus {
  final String driverId;
  final String busNumber;
  final Position? location;
  final DriverAlertLevel alertLevel;
  final DateTime lastUpdate;
  final bool isDrowsy;
  final int closedEyeFrames;
  final bool isOnline;

  DriverStatus({
    required this.driverId,
    required this.busNumber,
    this.location,
    this.alertLevel = DriverAlertLevel.none,
    required this.lastUpdate,
    this.isDrowsy = false,
    this.closedEyeFrames = 0,
    this.isOnline = true,
  });

  factory DriverStatus.fromMap(Map<String, dynamic> map, String id) {
    return DriverStatus(
      driverId: id,
      busNumber: map['busNumber'] ?? '',
      location: map['location'] != null
          ? Position(
              latitude: map['location']['latitude'],
              longitude: map['location']['longitude'],
              timestamp: (map['location']['timestamp'] as Timestamp).toDate(),
              accuracy: map['location']['accuracy'] ?? 0.0,
              altitude: map['location']['altitude'] ?? 0.0,
              heading: map['location']['heading'] ?? 0.0,
              speed: map['location']['speed'] ?? 0.0,
              speedAccuracy: map['location']['speedAccuracy'] ?? 0.0,
              altitudeAccuracy: 0.0,
              headingAccuracy: 0.0,
            )
          : null,
      alertLevel: DriverAlertLevel.values.firstWhere(
        (e) => e.toString().split('.').last == (map['alertLevel'] ?? 'none'),
        orElse: () => DriverAlertLevel.none,
      ),
      lastUpdate: (map['lastUpdate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDrowsy: map['isDrowsy'] ?? false,
      closedEyeFrames: map['closedEyeFrames'] ?? 0,
      isOnline: map['isOnline'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'busNumber': busNumber,
      'location': location != null
          ? {
              'latitude': location!.latitude,
              'longitude': location!.longitude,
              'timestamp': Timestamp.fromDate(location!.timestamp),
              'accuracy': location!.accuracy,
              'altitude': location!.altitude,
              'heading': location!.heading,
              'speed': location!.speed,
              'speedAccuracy': location!.speedAccuracy,
            }
          : null,
      'alertLevel': alertLevel.toString().split('.').last,
      'lastUpdate': FieldValue.serverTimestamp(),
      'isDrowsy': isDrowsy,
      'closedEyeFrames': closedEyeFrames,
      'isOnline': isOnline,
    };
  }
}

class MonitoringService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  StreamSubscription<QuerySnapshot>? _driversSubscription;
  StreamSubscription<DocumentSnapshot>? _currentDriverSubscription;
  Timer? _heartbeatTimer;
  
  List<DriverStatus> _allDrivers = [];
  DriverStatus? _currentDriverStatus;
  bool _isMonitoring = false;

  List<DriverStatus> get allDrivers => _allDrivers;
  DriverStatus? get currentDriverStatus => _currentDriverStatus;
  bool get isMonitoring => _isMonitoring;

  // For headquarters dashboard - monitor all drivers
  void startMonitoringAllDrivers() {
    _driversSubscription = _firestore
        .collection('driver_status')
        .snapshots()
        .listen((snapshot) {
      _allDrivers = snapshot.docs
          .map((doc) => DriverStatus.fromMap(doc.data(), doc.id))
          .toList();
      notifyListeners();
    });
  }

  // For individual driver - start monitoring and reporting
  Future<void> startDriverMonitoring(String driverId, String busNumber) async {
    _isMonitoring = true;
    
    // Initialize driver status document
    await _firestore.collection('driver_status').doc(driverId).set({
      'busNumber': busNumber,
      'isOnline': true,
      'alertLevel': 'none',
      'isDrowsy': false,
      'closedEyeFrames': 0,
      'lastUpdate': FieldValue.serverTimestamp(),
    });

    // Listen to own status updates
    _currentDriverSubscription = _firestore
        .collection('driver_status')
        .doc(driverId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        _currentDriverStatus = DriverStatus.fromMap(snapshot.data()!, snapshot.id);
        notifyListeners();
      }
    });

    // Start heartbeat
    _startHeartbeat(driverId);
    
    notifyListeners();
  }

  // Update driver location
  Future<void> updateDriverLocation(String driverId, Position position) async {
    if (!_isMonitoring) return;

    try {
      await _firestore.collection('driver_status').doc(driverId).update({
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': Timestamp.fromDate(position.timestamp),
          'accuracy': position.accuracy,
          'altitude': position.altitude,
          'heading': position.heading,
          'speed': position.speed,
          'speedAccuracy': position.speedAccuracy,
        },
        'lastUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  // Update drowsiness status
  Future<void> updateDrowsinessStatus(
    String driverId, 
    bool isDrowsy, 
    int closedEyeFrames
  ) async {
    if (!_isMonitoring) return;

    DriverAlertLevel alertLevel = DriverAlertLevel.none;
    
    if (isDrowsy) {
      if (closedEyeFrames > 30) {
        alertLevel = DriverAlertLevel.severe;
      } else if (closedEyeFrames > 20) {
        alertLevel = DriverAlertLevel.moderate;
      } else if (closedEyeFrames > 15) {
        alertLevel = DriverAlertLevel.mild;
      }
    }

    try {
      await _firestore.collection('driver_status').doc(driverId).update({
        'isDrowsy': isDrowsy,
        'closedEyeFrames': closedEyeFrames,
        'alertLevel': alertLevel.toString().split('.').last,
        'lastUpdate': FieldValue.serverTimestamp(),
      });

      // If severe alert, also log to incidents collection
      if (alertLevel == DriverAlertLevel.severe) {
        await _logIncident(driverId, 'SEVERE_DROWSINESS', {
          'closedEyeFrames': closedEyeFrames,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error updating drowsiness status: $e');
    }
  }

  // Log critical incidents
  Future<void> _logIncident(String driverId, String incidentType, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('incidents').add({
        'driverId': driverId,
        'incidentType': incidentType,
        'timestamp': FieldValue.serverTimestamp(),
        'data': data,
        'resolved': false,
      });
    } catch (e) {
      debugPrint('Error logging incident: $e');
    }
  }

  // Heartbeat to keep connection alive
  void _startHeartbeat(String driverId) {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isMonitoring) {
        _firestore.collection('driver_status').doc(driverId).update({
          'lastUpdate': FieldValue.serverTimestamp(),
        }).catchError((error) {
          debugPrint('Heartbeat error: $error');
        });
      }
    });
  }

  // Stop monitoring
  Future<void> stopMonitoring(String driverId) async {
    _isMonitoring = false;
    
    // Update status to offline
    try {
      await _firestore.collection('driver_status').doc(driverId).update({
        'isOnline': false,
        'lastUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating offline status: $e');
    }

    // Cancel subscriptions and timers
    _currentDriverSubscription?.cancel();
    _heartbeatTimer?.cancel();
    
    _currentDriverStatus = null;
    notifyListeners();
  }

  // Get driver history
  Future<List<Map<String, dynamic>>> getDriverHistory(String driverId, DateTime from, DateTime to) async {
    try {
      final query = await _firestore
          .collection('driver_history')
          .where('driverId', isEqualTo: driverId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(to))
          .orderBy('timestamp', descending: true)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error getting driver history: $e');
      return [];
    }
  }

  // Get incidents for a driver
  Future<List<Map<String, dynamic>>> getDriverIncidents(String driverId) async {
    try {
      final query = await _firestore
          .collection('incidents')
          .where('driverId', isEqualTo: driverId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      return query.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error getting incidents: $e');
      return [];
    }
  }

  @override
  void dispose() {
    _driversSubscription?.cancel();
    _currentDriverSubscription?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}