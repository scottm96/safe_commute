import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

enum UserType { driver, passenger }

class AppUser {
  final String id;
  final String email;
  final UserType userType;
  final String? ticketNumber;
  final String? companyId;
  final String? busNumber;
  final bool isActive;

  AppUser({
    required this.id,
    required this.email,
    required this.userType,
    this.ticketNumber,
    this.companyId,
    this.busNumber,
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

  // Driver Login
  Future<bool> loginDriver(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      // First verify the driver exists in the company database
      final driverQuery = await _firestore
          .collection('drivers')
          .where('email', isEqualTo: email)
          .where('isActive', isEqualTo: true)
          .get();

      if (driverQuery.docs.isEmpty) {
        _setError('Driver not found or inactive');
        return false;
      }

      final driverData = driverQuery.docs.first.data();
      
      // Verify password hash
      final hashedPassword = sha256.convert(utf8.encode(password)).toString();
      if (driverData['passwordHash'] != hashedPassword) {
        _setError('Invalid password');
        return false;
      }

      // Check if driver is already logged in
      if (driverData['currentSession'] != null) {
        _setError('Driver already has an active session');
        return false;
      }

      // Create Firebase Auth user or sign in
      UserCredential userCredential;
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (e) {
        // If user doesn't exist in Auth, create them
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      // Create/update user document
      final appUser = AppUser(
        id: userCredential.user!.uid,
        email: email,
        userType: UserType.driver,
        companyId: driverData['companyId'],
        busNumber: driverData['busNumber'],
      );

      await _firestore.collection('users').doc(appUser.id).set(appUser.toMap());

      // Update driver session
      await _firestore
          .collection('drivers')
          .doc(driverQuery.docs.first.id)
          .update({
        'currentSession': userCredential.user!.uid,
        'lastLogin': FieldValue.serverTimestamp(),
      });

      _currentUser = appUser;
      return true;

    } catch (e) {
      _setError('Login failed: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Passenger Login
  Future<bool> loginPassenger(String ticketNumber) async {
    _setLoading(true);
    _clearError();

    try {
      // Verify ticket exists and is valid
      final ticketQuery = await _firestore
          .collection('tickets')
          .where('ticketNumber', isEqualTo: ticketNumber)
          .where('isValid', isEqualTo: true)
          .where('isUsed', isEqualTo: false)
          .get();

      if (ticketQuery.docs.isEmpty) {
        _setError('Invalid or used ticket number');
        return false;
      }

      final ticketData = ticketQuery.docs.first.data();
      
      // Check if ticket already has an active session
      if (ticketData['currentSession'] != null) {
        _setError('Ticket is already in use');
        return false;
      }

      // Create anonymous user for passenger
      final userCredential = await _auth.signInAnonymously();

      // Create user document
      final appUser = AppUser(
        id: userCredential.user!.uid,
        email: 'passenger_$ticketNumber@temp.com',
        userType: UserType.passenger,
        ticketNumber: ticketNumber,
      );

      await _firestore.collection('users').doc(appUser.id).set(appUser.toMap());

      // Update ticket session
      await _firestore
          .collection('tickets')
          .doc(ticketQuery.docs.first.id)
          .update({
        'currentSession': userCredential.user!.uid,
        'lastUsed': FieldValue.serverTimestamp(),
      });

      _currentUser = appUser;
      return true;

    } catch (e) {
      _setError('Login failed: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Logout
  Future<void> logout() async {
    _setLoading(true);

    try {
      if (_currentUser != null) {
        // Clear sessions in respective collections
        if (_currentUser!.userType == UserType.driver) {
          await _clearDriverSession();
        } else {
          await _clearPassengerSession();
        }

        // Remove user document
        await _firestore.collection('users').doc(_currentUser!.id).delete();
      }

      await _auth.signOut();
      _currentUser = null;

    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _clearDriverSession() async {
    if (_currentUser?.companyId != null) {
      final driverQuery = await _firestore
          .collection('drivers')
          .where('currentSession', isEqualTo: _currentUser!.id)
          .get();

      for (final doc in driverQuery.docs) {
        await doc.reference.update({'currentSession': null});
      }
    }
  }

  Future<void> _clearPassengerSession() async {
    if (_currentUser?.ticketNumber != null) {
      final ticketQuery = await _firestore
          .collection('tickets')
          .where('currentSession', isEqualTo: _currentUser!.id)
          .get();

      for (final doc in ticketQuery.docs) {
        await doc.reference.update({'currentSession': null});
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
}