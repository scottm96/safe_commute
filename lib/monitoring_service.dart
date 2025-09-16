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
              timestamp: (map['location']['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
              accuracy: (map['location']['accuracy'] ?? 0.0).toDouble(),
              altitude: (map['location']['altitude'] ?? 0.0).toDouble(),
              heading: (map['location']['heading'] ?? 0.0).toDouble(),
              speed: (map['location']['speed'] ?? 0.0).toDouble(),
              speedAccuracy: (map['location']['speedAccuracy'] ?? 0.0).toDouble(),
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
  DriverStatus? _currentDriverStatus;
  StreamSubscription<QuerySnapshot>? _driversSubscription;
  StreamSubscription<QuerySnapshot>? _currentDriverSubscription;
  Timer? _heartbeatTimer;
  bool _isMonitoring = false;
  String? _currentBusNumber; // For specific monitoring

  DriverStatus? get currentDriverStatus => _currentDriverStatus;

  // Start monitoring all drivers (for passenger overview)
  Future<void> startMonitoringAllDrivers() async {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _subscribeToAllDrivers();
    _startHeartbeat(null); // General heartbeat
  }

  // Start monitoring specific driver by busNumber (for passenger after booking)
  Future<void> startMonitoringSpecificDriver(String busNumber) async {
    _currentBusNumber = busNumber;
    if (_isMonitoring) {
      _unsubscribeFromCurrentDriver();
      _driversSubscription?.cancel();
    }
    _isMonitoring = true;
    _subscribeToSpecificDriver(busNumber);
    _startHeartbeat(busNumber);
  }

  void _subscribeToAllDrivers() {
    _driversSubscription = _firestore
        .collection('driver_status')
        .where('companyId', isEqualTo: 'COMPANY_001')
        .snapshots()
        .listen((snapshot) {
      // Update all, but set current to first active or something; for simplicity, log
      debugPrint('Updated all drivers: ${snapshot.docs.length}');
      notifyListeners();
    });
  }

  void _subscribeToSpecificDriver(String busNumber) {
    _currentDriverSubscription = _firestore
        .collection('driver_status')
        .where('busNumber', isEqualTo: busNumber)
        .where('companyId', isEqualTo: 'COMPANY_001')
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        _currentDriverStatus = DriverStatus.fromMap(snapshot.docs.first.data(), snapshot.docs.first.id);
      } else {
        _currentDriverStatus = null;
      }
      notifyListeners();
    });
  }

  void _unsubscribeFromCurrentDriver() {
    _currentDriverSubscription?.cancel();
    _currentDriverSubscription = null;
  }

  // Log incident
  Future<void> logIncident(String driverId, String type, String description) async {
    try {
      await _firestore.collection('incidents').add({
        'driverId': driverId,
        'type': type,
        'description': description,
        'timestamp': FieldValue.serverTimestamp(),
        'severity': type.contains('SEVERE') ? 'high' : 'medium',
        'companyId': 'COMPANY_001',
      });
    } catch (e) {
      debugPrint('Error logging incident: $e');
    }
  }

  // Update driver status
  Future<void> updateDriverStatus(DriverStatus status) async {
    try {
      await _firestore.collection('driver_status').doc(status.driverId).set(
        status.toMap(),
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error updating driver status: $e');
    }
  }

  // Log trip start
  Future<void> logTripStart(String scheduleId, String driverId, Map<String, dynamic> startLocation) async {
    try {
      await _firestore.collection('schedules').doc(scheduleId).update({
        'status': 'in_transit',
        'actualDeparture': FieldValue.serverTimestamp(),
        'departureLocation': startLocation,
      });
      await _firestore.collection('drivers').doc(driverId).update({
        'currentSchedule': scheduleId,
        'status': 'driving',
      });
    } catch (e) {
      debugPrint('Error logging trip start: $e');
      rethrow;
    }
  }

  // Log trip end
  Future<void> logTripEnd(String scheduleId, String driverId, Map<String, dynamic> endLocation) async {
    try {
      await _firestore.collection('schedules').doc(scheduleId).update({
        'status': 'completed',
        'actualArrival': FieldValue.serverTimestamp(),
        'arrivalLocation': endLocation,
      });
      await _firestore.collection('drivers').doc(driverId).update({
        'currentSchedule': null,
        'status': 'available',
      });
      // Get busId and update availability
      final schedDoc = await _firestore.collection('schedules').doc(scheduleId).get();
      final busId = schedDoc.data()?['busId'];
      if (busId != null) {
        await _firestore.collection('buses').doc(busId).update({'isAvailable': true});
      }
    } catch (e) {
      debugPrint('Error logging trip end: $e');
      rethrow;
    }
  }

  // Heartbeat to keep connection alive
  void _startHeartbeat(String? busNumber) {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isMonitoring) {
        final driverId = _currentDriverStatus?.driverId ?? 'general';
        _firestore.collection('driver_status').doc(driverId).update({
          'lastUpdate': FieldValue.serverTimestamp(),
          'isOnline': true,
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
    _driversSubscription?.cancel();
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
          .where('companyId', isEqualTo: 'COMPANY_001')
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