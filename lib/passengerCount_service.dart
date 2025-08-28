import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PassengerCountService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  int _currentPassengerCount = 0;
  int _totalPassengersToday = 0;
  List<Map<String, dynamic>> _passengerLog = [];

  int get currentPassengerCount => _currentPassengerCount;
  int get totalPassengersToday => _totalPassengersToday;
  List<Map<String, dynamic>> get passengerLog => _passengerLog;

  // Initialize passenger count for driver session
  Future<void> initializePassengerCount(String driverId, String busNumber) async {
    try {
      // Get today's passenger data
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      final passengerQuery = await _firestore
          .collection('passenger_events')
          .where('driverId', isEqualTo: driverId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .orderBy('timestamp', descending: true)
          .get();

      int currentCount = 0;
      int totalToday = 0;
      _passengerLog.clear();

      for (var doc in passengerQuery.docs) {
        final data = doc.data();
        _passengerLog.add({
          'id': doc.id,
          'type': data['eventType'], // 'board' or 'alight'
          'timestamp': data['timestamp'],
          'location': data['location'],
        });

        if (data['eventType'] == 'board') {
          currentCount++;
          totalToday++;
        } else if (data['eventType'] == 'alight') {
          currentCount--;
        }
      }

      _currentPassengerCount = currentCount > 0 ? currentCount : 0;
      _totalPassengersToday = totalToday;
      
      // Update Firebase with current count
      await _updateBusPassengerCount(driverId, _currentPassengerCount);
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing passenger count: $e');
    }
  }

  // Record passenger boarding
  Future<void> recordPassengerBoard(String driverId, String busNumber, {
    double? latitude,
    double? longitude,
    String? stopName,
  }) async {
    try {
      await _firestore.collection('passenger_events').add({
        'driverId': driverId,
        'busNumber': busNumber,
        'eventType': 'board',
        'timestamp': FieldValue.serverTimestamp(),
        'location': latitude != null && longitude != null ? {
          'latitude': latitude,
          'longitude': longitude,
          'stopName': stopName,
        } : null,
      });

      _currentPassengerCount++;
      _totalPassengersToday++;
      
      // Update bus status in Firebase
      await _updateBusPassengerCount(driverId, _currentPassengerCount);
      
      notifyListeners();
      debugPrint('Passenger boarded. Current count: $_currentPassengerCount');
    } catch (e) {
      debugPrint('Error recording passenger board: $e');
    }
  }

  // Record passenger alighting
  Future<void> recordPassengerAlight(String driverId, String busNumber, {
    double? latitude,
    double? longitude,
    String? stopName,
  }) async {
    if (_currentPassengerCount <= 0) {
      debugPrint('Cannot alight passenger - no passengers on board');
      return;
    }

    try {
      await _firestore.collection('passenger_events').add({
        'driverId': driverId,
        'busNumber': busNumber,
        'eventType': 'alight',
        'timestamp': FieldValue.serverTimestamp(),
        'location': latitude != null && longitude != null ? {
          'latitude': latitude,
          'longitude': longitude,
          'stopName': stopName,
        } : null,
      });

      _currentPassengerCount--;
      if (_currentPassengerCount < 0) _currentPassengerCount = 0;
      
      // Update bus status in Firebase
      await _updateBusPassengerCount(driverId, _currentPassengerCount);
      
      notifyListeners();
      debugPrint('Passenger alighted. Current count: $_currentPassengerCount');
    } catch (e) {
      debugPrint('Error recording passenger alight: $e');
    }
  }

  // Update passenger count in bus status (for HQ dashboard)
  Future<void> _updateBusPassengerCount(String driverId, int count) async {
    try {
      await _firestore.collection('driver_status').doc(driverId).update({
        'passengerCount': count,
        'lastPassengerUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating bus passenger count: $e');
    }
  }

  // Manual count adjustment (for corrections)
  Future<void> adjustPassengerCount(String driverId, String busNumber, int newCount) async {
    if (newCount < 0) newCount = 0;
    
    try {
      // Log the manual adjustment
      await _firestore.collection('passenger_events').add({
        'driverId': driverId,
        'busNumber': busNumber,
        'eventType': 'manual_adjustment',
        'timestamp': FieldValue.serverTimestamp(),
        'oldCount': _currentPassengerCount,
        'newCount': newCount,
      });

      _currentPassengerCount = newCount;
      
      // Update bus status
      await _updateBusPassengerCount(driverId, _currentPassengerCount);
      
      notifyListeners();
      debugPrint('Passenger count manually adjusted to: $_currentPassengerCount');
    } catch (e) {
      debugPrint('Error adjusting passenger count: $e');
    }
  }

  // Get passenger statistics
  Future<Map<String, dynamic>> getPassengerStats(String driverId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final startOfWeek = today.subtract(Duration(days: 7));
      
      // Today's stats
      final todayQuery = await _firestore
          .collection('passenger_events')
          .where('driverId', isEqualTo: driverId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();

      // Week's stats
      final weekQuery = await _firestore
          .collection('passenger_events')
          .where('driverId', isEqualTo: driverId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
          .get();

      int todayBoards = 0;
      int todayAlights = 0;
      int weekBoards = 0;
      int weekAlights = 0;

      for (var doc in todayQuery.docs) {
        final eventType = doc.data()['eventType'];
        if (eventType == 'board') todayBoards++;
        if (eventType == 'alight') todayAlights++;
      }

      for (var doc in weekQuery.docs) {
        final eventType = doc.data()['eventType'];
        if (eventType == 'board') weekBoards++;
        if (eventType == 'alight') weekAlights++;
      }

      return {
        'todayBoards': todayBoards,
        'todayAlights': todayAlights,
        'weekBoards': weekBoards,
        'weekAlights': weekAlights,
        'currentCount': _currentPassengerCount,
      };
    } catch (e) {
      debugPrint('Error getting passenger stats: $e');
      return {
        'todayBoards': 0,
        'todayAlights': 0,
        'weekBoards': 0,
        'weekAlights': 0,
        'currentCount': _currentPassengerCount,
      };
    }
  }

  // Reset count (for end of shift)
  Future<void> resetPassengerCount(String driverId, String busNumber) async {
    try {
      // Log the reset event
      await _firestore.collection('passenger_events').add({
        'driverId': driverId,
        'busNumber': busNumber,
        'eventType': 'shift_end_reset',
        'timestamp': FieldValue.serverTimestamp(),
        'finalCount': _currentPassengerCount,
      });

      _currentPassengerCount = 0;
      
      // Update bus status
      await _updateBusPassengerCount(driverId, 0);
      
      notifyListeners();
      debugPrint('Passenger count reset for end of shift');
    } catch (e) {
      debugPrint('Error resetting passenger count: $e');
    }
  }
}