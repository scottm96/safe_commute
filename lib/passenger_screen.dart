import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'monitoring_service.dart';
import 'location_service.dart';
import 'passenger_map_widget.dart';
import 'dart:async';

class PassengerScreen extends StatefulWidget {
  const PassengerScreen({super.key});

  @override
  State<PassengerScreen> createState() => _PassengerScreenState();
}

class _PassengerScreenState extends State<PassengerScreen> {
  Timer? _locationUpdateTimer;
  final _complaintController = TextEditingController();
  bool _isSubmittingComplaint = false;
  String? _complaintError;
  bool _complaintSubmitted = false;
  bool _showMapView = true;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    final monitoring = context.read<MonitoringService>();
    final location = context.read<LocationService>();

    // Start monitoring specific bus if available
    if (auth.currentUser?.busNumber != null) {
      monitoring.startMonitoringSpecificDriver(auth.currentUser!.busNumber!);
    } else {
      monitoring.startMonitoringAllDrivers(); // Fallback
    }

    // Start passenger location tracking
    _startPassengerLocationTracking();
  }

  void _startPassengerLocationTracking() async {
    final locationService = context.read<LocationService>();
    final auth = context.read<AuthService>();

    if (auth.currentUser != null) {
      bool locationStarted = await locationService.startLocationTracking(
        onLocationUpdate: (Position position) {
          _updatePassengerLocation(position);
        },
      );

      if (locationStarted) {
        debugPrint("Passenger location tracking started successfully");
        _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
          final position = await locationService.getCurrentLocation();
          if (position != null) {
            _updatePassengerLocation(position);
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions required for safety features'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  Future<void> _updatePassengerLocation(Position position) async {
    final auth = context.read<AuthService>();
    if (auth.currentUser == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('passenger_locations')
          .doc(auth.currentUser!.id)
          .set({
        'passengerId': auth.currentUser!.id,
        'ticketNumber': auth.currentUser!.ticketNumber,
        'busNumber': auth.currentUser!.busNumber, // Link to bus
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'accuracy': position.accuracy,
          'speed': position.speed,
        },
        'lastUpdate': FieldValue.serverTimestamp(),
        'isActive': true,
        'companyId': 'COMPANY_001',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating passenger location: $e');
    }
  }

  void _centerMapOnMyLocation() async {
    final locationService = context.read<LocationService>();
    final position = await locationService.getCurrentLocation();
    
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to get location')));
      return;
    }

    // Animate map to user location (implement via map controller if using flutter_map)
    debugPrint('Centering map on: ${position.latitude}, ${position.longitude}');
  }

  Future<void> _submitComplaint() async {
    if (_complaintController.text.trim().isEmpty) {
      setState(() => _complaintError = 'Complaint cannot be empty');
      return;
    }

    setState(() {
      _isSubmittingComplaint = true;
      _complaintError = null;
    });

    final auth = context.read<AuthService>();
    try {
      await FirebaseFirestore.instance.collection('complaints').add({
        'name': auth.currentUser?.email ?? 'Anonymous',
        'ticketNumber': auth.currentUser?.ticketNumber,
        'busNumber': auth.currentUser?.busNumber,
        'complaint': _complaintController.text.trim(),
        'status': 'pending',
        'source': 'mobile',
        'companyId': 'COMPANY_001',
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _complaintSubmitted = true;
        _complaintController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complaint submitted successfully'), backgroundColor: Colors.green),
      );
    } catch (e) {
      setState(() => _complaintError = 'Failed to submit: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSubmittingComplaint = false);
    }
  }

  void _showComplaintDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Report Issue'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _complaintController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Describe the issue (e.g., driver behavior, comfort)...',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_complaintError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_complaintError!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _complaintController.clear();
                setState(() {
                  _complaintError = null;
                  _complaintSubmitted = false;
                });
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isSubmittingComplaint ? null : () async {
                await _submitComplaint();
                if (_complaintSubmitted) {
                  Navigator.of(context).pop();
                  setState(() {
                    _complaintError = null;
                    _complaintSubmitted = false;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: _isSubmittingComplaint
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emergency, color: Colors.red),
            SizedBox(width: 8),
            Text('Emergency Contacts'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'In case of emergency, contact:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('🚨 Emergency Services: 191 (Ghana Police)'),
            SizedBox(height: 8),
            Text('🚌 Transport Authority: +233-302-221-xxx'),
            SizedBox(height: 8),
            Text('👮 Police: 191'),
            SizedBox(height: 16),
            Text(
              'Your location is tracked and shared with authorities if needed.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Integrate phone call
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Calling emergency services...'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Call 191'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _complaintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final location = Provider.of<LocationService>(context);
    final monitoring = Provider.of<MonitoringService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Passenger Dashboard - ${auth.currentUser?.routeName ?? 'Your Trip'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning),
            onPressed: _showComplaintDialog,
          ),
          IconButton(
            icon: const Icon(Icons.emergency),
            onPressed: _showEmergencyDialog,
            color: Colors.red,
          ),
        ],
      ),
      body: Column(
        children: [
          // Trip Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text('Bus: ${auth.currentUser?.busNumber ?? 'TBA'}'),
                  Text('Route: ${auth.currentUser?.routeName ?? ''}'),
                  Text('From: ${auth.currentUser?.origin ?? ''} to ${auth.currentUser?.destination ?? ''}'),
                  if (auth.currentUser?.ticketNumber != null) Text('Ticket: ${auth.currentUser!.ticketNumber}'),
                ],
              ),
            ),
          ),
          Expanded(
            child: Consumer2<LocationService, MonitoringService>(
              builder: (context, location, monitoring, child) {
                return Stack(
                  children: [
                    PassengerMapWidget(
                      passengerLocation: location.currentPosition,
                      driverStatus: monitoring.currentDriverStatus,
                      onMyLocationPressed: _centerMapOnMyLocation,
                    ),
                    if (location.errorMessage != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            location.errorMessage!,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerMapOnMyLocation,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}