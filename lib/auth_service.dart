import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'user_type.dart';

class AppUser {
  final String id;
  final String email;
  final UserType userType;
  final String? ticketNumber;
  final String? companyId;
  final String? busNumber;
  final String? routeName;
  final String? origin;
  final String? destination;
  final bool isActive;
  // NEW: Add passenger name field
  final String? passengerName;
  final String? phoneNumber;

  AppUser({
    required this.id,
    required this.email,
    required this.userType,
    this.ticketNumber,
    this.companyId,
    this.busNumber,
    this.routeName,
    this.origin,
    this.destination,
    this.isActive = true,
    this.passengerName,
    this.phoneNumber,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String id) {
    return AppUser(
      id: id,
      email: map['email'] ?? '',
      userType: map['userType'] == 'driver' ? UserType.driver : UserType.passenger,
      ticketNumber: map['ticketNumber'],
      companyId: map['companyId'],
      busNumber: map['busNumber'],
      routeName: map['routeName'],
      origin: map['origin'],
      destination: map['destination'],
      isActive: map['isActive'] ?? true,
      passengerName: map['passengerName'],
      phoneNumber: map['phoneNumber'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'userType': userType == UserType.driver ? 'driver' : 'passenger',
      'ticketNumber': ticketNumber,
      'companyId': companyId,
      'busNumber': busNumber,
      'routeName': routeName,
      'origin': origin,
      'destination': destination,
      'isActive': isActive,
      'passengerName': passengerName,
      'phoneNumber': phoneNumber,
      'lastSeen': FieldValue.serverTimestamp(),
    };
  }
}

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AppUser? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  AuthService() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  void _onAuthStateChanged(User? user) async {
    if (user != null) {
      await _loadUserData(user.uid);
    } else {
      _currentUser = null;
      notifyListeners();
    }
  }

  Future<void> _loadUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        _currentUser = AppUser.fromMap(doc.data()!, uid);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  // Fixed Driver Login (unchanged)
  Future<bool> loginDriver(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      final driverQuery = await _firestore
          .collection('drivers')
          .where('email', isEqualTo: email)
          .where('companyId', isEqualTo: 'COMPANY_001')
          .limit(1)
          .get();

      if (driverQuery.docs.isEmpty) {
        _setError('Driver not found');
        return false;
      }

      final driverData = driverQuery.docs.first.data();
      final hashedPassword = sha256.convert(utf8.encode(password)).toString();

      if (driverData['passwordHash'] != hashedPassword) {
        _setError('Invalid password');
        return false;
      }

      UserCredential? userCredential;
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email, 
          password: password
        );
      } catch (authError) {
        if (authError is FirebaseAuthException && 
            (authError.code == 'user-not-found' || authError.code == 'invalid-credential')) {
          debugPrint('Creating Firebase Auth account for existing driver');
          try {
            userCredential = await _auth.createUserWithEmailAndPassword(
              email: email,
              password: password
            );
            debugPrint('Firebase Auth account created successfully');
          } catch (createError) {
            debugPrint('Failed to create Firebase Auth account: $createError');
            _setError('Authentication setup failed');
            return false;
          }
        } else {
          debugPrint('Firebase Auth error: $authError');
          _setError('Authentication failed: ${authError.toString()}');
          return false;
        }
      }

      if (userCredential?.user == null) {
        _setError('Authentication failed');
        return false;
      }

      await _firestore.collection('drivers').doc(driverQuery.docs.first.id).update({
        'currentSession': userCredential!.user!.uid,
        'lastLogin': FieldValue.serverTimestamp(),
        'status': 'online',
      });

      await _firestore.collection('users').doc(userCredential.user!.uid).set(
        AppUser(
          id: userCredential.user!.uid,
          email: email,
          userType: UserType.driver,
          busNumber: driverData['busNumber'],
          companyId: driverData['companyId'],
        ).toMap(),
        SetOptions(merge: true),
      );

      await _firestore.collection('driver_status').doc(userCredential.user!.uid).set({
        'driverId': userCredential.user!.uid,
        'email': email,
        'busNumber': driverData['busNumber'],
        'companyId': driverData['companyId'],
        'status': 'online',
        'isActive': true,
        'currentLocation': null,
        'lastUpdate': FieldValue.serverTimestamp(),
        'currentSchedule': null,
      }, SetOptions(merge: true));

      _currentUser = AppUser(
        id: userCredential.user!.uid,
        email: email,
        userType: UserType.driver,
        busNumber: driverData['busNumber'],
        companyId: driverData['companyId'],
      );
      
      notifyListeners();
      return true;

    } catch (e) {
      debugPrint('Driver login error: $e');
      _setError('Login failed: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Add this method to AuthService class
  Future<bool> _isTicketValid(Map<String, dynamic> ticketData) async {
    // Check if ticket has expiration time
    if (ticketData['expiresAt'] != null) {
      final expirationTime = ticketData['expiresAt'] as Timestamp;
      final now = DateTime.now();
      
      if (now.isAfter(expirationTime.toDate())) {
        return false; // Ticket has expired
      }
    }
    
    return true; // Ticket is still valid
  }

  // UPDATED: Enhanced Passenger Login with Name Support
  Future<bool> loginPassenger(String ticketNumber) async {
    _setLoading(true);
    _clearError();

    try {
      // Search for ticket by ticket number
      final ticketQuery = await _firestore
          .collection('tickets')
          .where('ticketNumber', isEqualTo: ticketNumber)
          .where('companyId', isEqualTo: 'COMPANY_001')
          .limit(1)
          .get();

      if (ticketQuery.docs.isEmpty) {
        _setError('Invalid ticket number');
        return false;
      }

      final ticketData = ticketQuery.docs.first.data();
      
      // NEW: Check if ticket is already in use (has active session)
      if (ticketData['currentSession'] != null) {
        // Check if the session is still valid
        final existingUser = await _firestore
            .collection('users')
            .doc(ticketData['currentSession'])
            .get();
            
        if (existingUser.exists) {
          _setError('This ticket is already in use on another device');
          return false;
        } else {
          // Session is invalid, clear it
          await _firestore.collection('tickets').doc(ticketQuery.docs.first.id).update({
            'currentSession': null,
          });
        }
      }

      // NEW: Check if ticket is still valid (within 24 hours)
      if (!await _isTicketValid(ticketData)) {
        _setError('Ticket has expired (valid for 24 hours after booking)');
        return false;
      }

      // NEW: Allow login even if ticket was previously used (for multiple logins)
      // Remove the isUsed check to allow re-login with same ticket
      
      // Create anonymous account for passenger
      UserCredential userCredential;
      try {
        userCredential = await _auth.signInAnonymously();
      } catch (e) {
        debugPrint('Anonymous sign-in failed: $e');
        _setError('Authentication failed');
        return false;
      }

      // Add this after creating the ticket data
      await _firestore.collection('tickets').doc(ticketQuery.docs.first.id).update({
        'currentSession': userCredential.user!.uid,
        'lastLogin': FieldValue.serverTimestamp(),
        'expiresAt': FieldValue.serverTimestamp(), // Add expiration timestamp
      });

      // Create user document with passenger details from ticket
      await _firestore.collection('users').doc(userCredential.user!.uid).set(
        AppUser(
          id: userCredential.user!.uid,
          email: '${ticketNumber}@safecommute.gh', // Keep for compatibility
          userType: UserType.passenger,
          ticketNumber: ticketNumber,
          busNumber: ticketData['busNumber'],
          routeName: ticketData['routeName'],
          origin: ticketData['origin'],
          destination: ticketData['destination'],
          companyId: ticketData['companyId'],
          // NEW: Store passenger name and phone from ticket
          passengerName: ticketData['passengerName'],
          phoneNumber: ticketData['phoneNumber'] ?? ticketData['phone'],
        ).toMap(),
        SetOptions(merge: true),
      );

      _currentUser = AppUser.fromMap({
        'email': '${ticketNumber}@safecommute.gh',
        'userType': 'passenger',
        'ticketNumber': ticketNumber,
        'busNumber': ticketData['busNumber'],
        'routeName': ticketData['routeName'],
        'origin': ticketData['origin'],
        'destination': ticketData['destination'],
        'companyId': ticketData['companyId'],
        // NEW: Include passenger name and phone
        'passengerName': ticketData['passengerName'],
        'phoneNumber': ticketData['phoneNumber'] ?? ticketData['phone'],
      }, userCredential.user!.uid);
      
      notifyListeners();
      return true;
      
    } catch (e) {
      debugPrint('Passenger login error: $e');
      _setError('Login failed: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // UPDATED: Enhanced Logout
  Future<void> logout() async {
    _setLoading(true);

    try {
      if (_currentUser != null) {
        if (_currentUser!.userType == UserType.driver) {
          await _clearDriverSession();
        } else {
          await _clearPassengerSession();
        }

        try {
          await _firestore.collection('users').doc(_currentUser!.id).delete();
        } catch (e) {
          debugPrint('Error deleting user document: $e');
        }

        if (_currentUser!.userType == UserType.driver) {
          try {
            await _firestore.collection('driver_status').doc(_currentUser!.id).delete();
          } catch (e) {
            debugPrint('No driver status to delete: $e');
          }
        }
      }

      await _auth.signOut();
      _currentUser = null;
      _clearError();
      
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _clearDriverSession() async {
    if (_currentUser?.companyId != null) {
      try {
        final driverQuery = await _firestore
            .collection('drivers')
            .where('currentSession', isEqualTo: _currentUser!.id)
            .get();

        for (final doc in driverQuery.docs) {
          await doc.reference.update({
            'currentSession': null,
            'status': 'offline',
          });
        }
      } catch (e) {
        debugPrint('Error clearing driver session: $e');
      }
    }
  }

  Future<void> _clearPassengerSession() async {
    if (_currentUser?.ticketNumber != null) {
      try {
        final ticketQuery = await _firestore
            .collection('tickets')
            .where('currentSession', isEqualTo: _currentUser!.id)
            .get();

        for (final doc in ticketQuery.docs) {
          await doc.reference.update({'currentSession': null});
        }
      } catch (e) {
        debugPrint('Error clearing passenger session: $e');
      }
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Helper method to create driver accounts (for testing/setup)
  Future<bool> createDriverAccount(String email, String password, Map<String, dynamic> driverData) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final hashedPassword = sha256.convert(utf8.encode(password)).toString();

      await _firestore.collection('drivers').add({
        ...driverData,
        'email': email,
        'passwordHash': hashedPassword,
        'companyId': 'COMPANY_001',
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'currentSession': null,
        'status': 'offline',
      });

      await _auth.signOut();
      return true;
      
    } catch (e) {
      debugPrint('Error creating driver account: $e');
      return false;
    }
  }

  // NEW: Method to check ticket status
  Future<Map<String, dynamic>?> getTicketInfo(String ticketNumber) async {
    try {
      final ticketQuery = await _firestore
          .collection('tickets')
          .where('ticketNumber', isEqualTo: ticketNumber)
          .where('companyId', isEqualTo: 'COMPANY_001')
          .limit(1)
          .get();

      if (ticketQuery.docs.isEmpty) {
        return null;
      }

      final ticketData = ticketQuery.docs.first.data();
      return {
        ...ticketData,
        'id': ticketQuery.docs.first.id,
      };
    } catch (e) {
      debugPrint('Error getting ticket info: $e');
      return null;
    }
  }

  
  Future<void> markTicketAsUsed(String ticketNumber) async {
    try {
      final ticketQuery = await _firestore
          .collection('tickets')
          .where('ticketNumber', isEqualTo: ticketNumber)
          .where('companyId', isEqualTo: 'COMPANY_001')
          .limit(1)
          .get();

      if (ticketQuery.docs.isNotEmpty) {
        await _firestore.collection('tickets').doc(ticketQuery.docs.first.id).update({
          'isUsed': true,
          'usedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error marking ticket as used: $e');
    }
  }
}
