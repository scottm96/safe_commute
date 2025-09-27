import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

enum DriverAlertLevel { none, mild, moderate, severe }

// NEW: Passenger Alert class for drowsiness notifications
class PassengerAlert {
  final String id;
  final String busNumber;
  final String alertType;
  final String severity;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? metadata;

  PassengerAlert({
    required this.id,
    required this.busNumber,
    required this.alertType,
    required this.severity,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.metadata,
  });

  factory PassengerAlert.fromMap(Map<String, dynamic> map, String id) {
    return PassengerAlert(
      id: id,
      busNumber: map['busNumber'] ?? '',
      alertType: map['alertType'] ?? '',
      severity: map['severity'] ?? 'LOW',
      message: map['message'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: map['isRead'] ?? false,
      metadata: map['metadata'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'busNumber': busNumber,
      'alertType': alertType,
      'severity': severity,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': isRead,
      'metadata': metadata,
      'companyId': 'COMPANY_001',
    };
  }
}

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
  StreamSubscription<QuerySnapshot>? _passengerAlertsSubscription;
  Timer? _heartbeatTimer;
  bool _isMonitoring = false;
  String? _currentBusNumber;

  // NEW: Passenger alerts management
  List<PassengerAlert> _passengerAlerts = [];
  List<PassengerAlert> get passengerAlerts => _passengerAlerts;
  PassengerAlert? _latestDrowsinessAlert;
  PassengerAlert? get latestDrowsinessAlert => _latestDrowsinessAlert;

  bool get isMonitoring => _isMonitoring;
  DriverStatus? get currentDriverStatus => _currentDriverStatus;

  // Start monitoring all drivers (for passenger overview)
  Future<void> startMonitoringAllDrivers() async {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _subscribeToAllDrivers();
    _startHeartbeat(null);
    notifyListeners();
  }

  // Start monitoring specific driver by busNumber (for passenger after booking)
  Future<void> startMonitoringSpecificDriver(String busNumber) async {
    _currentBusNumber = busNumber;
    if (_isMonitoring) {
      _unsubscribeFromCurrentDriver();
      _driversSubscription?.cancel();
      _passengerAlertsSubscription?.cancel();
    }
    _isMonitoring = true;
    _subscribeToSpecificDriver(busNumber);
    _subscribeToPassengerAlerts(busNumber);
    _startHeartbeat(busNumber);
    notifyListeners();
  }

  void _subscribeToAllDrivers() {
    _driversSubscription = _firestore
        .collection('driver_status')
        .where('companyId', isEqualTo: 'COMPANY_001')
        .snapshots()
        .listen((snapshot) {
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

  // NEW: Subscribe to passenger alerts for specific bus
  void _subscribeToPassengerAlerts(String busNumber) {
    _passengerAlertsSubscription = _firestore
        .collection('passenger_alerts')
        .where('busNumber', isEqualTo: busNumber)
        .where('companyId', isEqualTo: 'COMPANY_001')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen((snapshot) {
      _passengerAlerts = snapshot.docs
          .map((doc) => PassengerAlert.fromMap(doc.data(), doc.id))
          .toList();
      
      // Update latest drowsiness alert
      _latestDrowsinessAlert = _passengerAlerts
          .where((alert) => alert.alertType == 'DRIVER_DROWSINESS')
          .isNotEmpty
          ? _passengerAlerts
              .where((alert) => alert.alertType == 'DRIVER_DROWSINESS')
              .first
          : null;
      
      debugPrint('Updated passenger alerts: ${_passengerAlerts.length}');
      if (_latestDrowsinessAlert != null) {
        debugPrint('Latest drowsiness alert: ${_latestDrowsinessAlert!.message}');
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

  // NEW: Create passenger alert (called by driver when drowsiness detected)
  Future<void> createPassengerAlert({
    required String busNumber,
    required String alertType,
    required String severity,
    required String message,
    required DateTime timestamp,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final alert = PassengerAlert(
        id: '',
        busNumber: busNumber,
        alertType: alertType,
        severity: severity,
        message: message,
        timestamp: timestamp,
        metadata: metadata,
      );

      await _firestore.collection('passenger_alerts').add(alert.toMap());
      debugPrint('Created passenger alert: $alertType for bus $busNumber');
    } catch (e) {
      debugPrint('Error creating passenger alert: $e');
    }
  }

  // NEW: Mark passenger alert as read
  Future<void> markAlertAsRead(String alertId) async {
    try {
      await _firestore.collection('passenger_alerts').doc(alertId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error marking alert as read: $e');
    }
  }

  // NEW: Get passenger alerts for specific bus (for manual fetch)
  Future<List<PassengerAlert>> getPassengerAlertsForBus(String busNumber) async {
    try {
      final query = await _firestore
          .collection('passenger_alerts')
          .where('busNumber', isEqualTo: busNumber)
          .where('companyId', isEqualTo: 'COMPANY_001')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      return query.docs
          .map((doc) => PassengerAlert.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error getting passenger alerts: $e');
      return [];
    }
  }

  // NEW: Check if there are unread drowsiness alerts
  bool get hasUnreadDrowsinessAlert {
    return _passengerAlerts
        .where((alert) => alert.alertType == 'DRIVER_DROWSINESS' && !alert.isRead)
        .isNotEmpty;
  }

  // NEW: Get latest drowsiness alert time
  DateTime? get latestDrowsinessAlertTime {
    final drowsinessAlerts = _passengerAlerts
        .where((alert) => alert.alertType == 'DRIVER_DROWSINESS')
        .toList();
    
    if (drowsinessAlerts.isEmpty) return null;
    return drowsinessAlerts.first.timestamp;
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
    _passengerAlertsSubscription?.cancel();
    _heartbeatTimer?.cancel();
    
    _currentDriverStatus = null;
    _passengerAlerts.clear();
    _latestDrowsinessAlert = null;
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
    _passengerAlertsSubscription?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}