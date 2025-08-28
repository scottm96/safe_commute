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
      userType:
          map['userType'] == 'driver' ? UserType.driver : UserType.passenger,
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

  // Driver Login with better error handling
  Future<bool> loginDriver(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      // First check if driver exists in Firestore
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

      if (driverData['currentSession'] != null) {
        _setError('Driver already has an active session');
        return false;
      }

      // Try Firebase authentication with better error handling
      UserCredential? userCredential;
      
      try {
        // First try to sign in
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (authError) {
        debugPrint('Sign in failed: ${authError.code} - ${authError.message}');
        
        // If user doesn't exist, try to create account
        if (authError.code == 'user-not-found' || 
            authError.code == 'invalid-credential' ||
            authError.code == 'invalid-email') {
          try {
            userCredential = await _auth.createUserWithEmailAndPassword(
              email: email,
              password: password,
            );
            debugPrint('Created new Firebase Auth user for driver');
          } on FirebaseAuthException catch (createError) {
            debugPrint('Account creation failed: ${createError.code} - ${createError.message}');
            _setError('Authentication failed: ${createError.message}');
            return false;
          }
        } else {
          _setError('Authentication failed: ${authError.message}');
          return false;
        }
      } catch (e) {
        debugPrint('Unexpected auth error: $e');
        _setError('Authentication failed: Unexpected error');
        return false;
      }

      if (userCredential.user == null) {
        _setError('Authentication failed: No user returned');
        return false;
      }

      final appUser = AppUser(
        id: userCredential.user!.uid,
        email: email,
        userType: UserType.driver,
        companyId: driverData['companyId'],
        busNumber: driverData['busNumber'],
      );

      // Create/update user document
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
      debugPrint('Driver login error: $e');
      _setError('Login failed: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Passenger Login with better error handling
  Future<bool> loginPassenger(String ticketNumber) async {
    _setLoading(true);
    _clearError();

    try {
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

      if (ticketData['currentSession'] != null) {
        _setError('Ticket is already in use');
        return false;
      }

      // Sign in anonymously with error handling
      UserCredential? userCredential;
      try {
        userCredential = await _auth.signInAnonymously();
      } on FirebaseAuthException catch (authError) {
        debugPrint('Anonymous sign in failed: ${authError.code} - ${authError.message}');
        _setError('Authentication failed: ${authError.message}');
        return false;
      } catch (e) {
        debugPrint('Unexpected anonymous auth error: $e');
        _setError('Authentication failed: Unexpected error');
        return false;
      }

      if (userCredential.user == null) {
        _setError('Authentication failed: No user returned');
        return false;
      }

      final appUser = AppUser(
        id: userCredential.user!.uid,
        email: 'passenger_$ticketNumber@temp.com',
        userType: UserType.passenger,
        ticketNumber: ticketNumber,
      );

      // Create user document
      await _firestore.collection('users').doc(appUser.id).set(appUser.toMap());

      // Update ticket session
      await _firestore
          .collection('tickets')
          .doc(ticketQuery.docs.first.id)
          .update({
        'currentSession': userCredential.user!.uid,
        'lastUsed': FieldValue.serverTimestamp(),
        'isUsed': true,
      });

      _currentUser = appUser;
      return true;
    } catch (e) {
      debugPrint('Passenger login error: $e');
      _setError('Login failed: ${e.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Logout with better error handling
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
        try {
          await _firestore.collection('driver_status').doc(_currentUser!.id).delete();
        } catch (e) {
          debugPrint('No driver status to delete: $e');
        }
      }

      // Sign out with error handling
      try {
        await _auth.signOut();
      } on FirebaseAuthException catch (e) {
        debugPrint('Sign out error: ${e.code} - ${e.message}');
      }
      
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
          await doc.reference.update({'currentSession': null});
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
}