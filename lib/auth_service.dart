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

  // Fixed Driver Login
  Future<bool> loginDriver(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      // First check if driver exists in Firestore
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

      // Try to sign in with Firebase Auth first
      UserCredential? userCredential;
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email, 
          password: password
        );
      } catch (authError) {
        // If Firebase Auth account doesn't exist, create it
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

      // Update driver session info
      await _firestore.collection('drivers').doc(driverQuery.docs.first.id).update({
        'currentSession': userCredential!.user!.uid,
        'lastLogin': FieldValue.serverTimestamp(),
        'status': 'online',
      });

      // Create/update user document
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

      // Create driver status document for real-time tracking
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

  // Passenger Login (Updated for Route/Bus Validation)
  Future<bool> loginPassenger(String ticketNumber) async {
    _setLoading(true);
    _clearError();

    try {
      final ticketQuery = await _firestore
          .collection('tickets')
          .where('ticketNumber', isEqualTo: ticketNumber)
          .where('companyId', isEqualTo: 'COMPANY_001')
          .where('isUsed', isEqualTo: false)
          .limit(1)
          .get();

      if (ticketQuery.docs.isEmpty) {
        _setError('Invalid or used ticket');
        return false;
      }

      final ticketData = ticketQuery.docs.first.data();
      
      // Create anonymous account for passenger
      UserCredential userCredential;
      try {
        userCredential = await _auth.signInAnonymously();
      } catch (e) {
        debugPrint('Anonymous sign-in failed: $e');
        _setError('Authentication failed');
        return false;
      }

      // Mark ticket as used and link session
      await _firestore.collection('tickets').doc(ticketQuery.docs.first.id).update({
        'isUsed': true,
        'currentSession': userCredential.user!.uid,
        'usedAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('users').doc(userCredential.user!.uid).set(
        AppUser(
          id: userCredential.user!.uid,
          email: '${ticketNumber}@safecommute.gh',
          userType: UserType.passenger,
          ticketNumber: ticketNumber,
          busNumber: ticketData['busNumber'],
          routeName: ticketData['routeName'],
          origin: ticketData['origin'],
          destination: ticketData['destination'],
          companyId: ticketData['companyId'],
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

  // Enhanced Logout
  Future<void> logout() async {
    _setLoading(true);

    try {
      if (_currentUser != null) {
        if (_currentUser!.userType == UserType.driver) {
          await _clearDriverSession();
        } else {
          await _clearPassengerSession();
        }

        // Delete user document
        try {
          await _firestore.collection('users').doc(_currentUser!.id).delete();
        } catch (e) {
          debugPrint('Error deleting user document: $e');
        }

        // Remove from driver_status if exists
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
      // Create Firebase Auth account
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Hash password for Firestore storage
      final hashedPassword = sha256.convert(utf8.encode(password)).toString();

      // Create driver document
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

      await _auth.signOut(); // Sign out after creation
      return true;
      
    } catch (e) {
      debugPrint('Error creating driver account: $e');
      return false;
    }
  }
}