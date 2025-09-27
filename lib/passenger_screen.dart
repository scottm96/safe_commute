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
        // FIXED: Use actual passenger name instead of generated email
        'name': auth.currentUser?.passengerName ?? 'Anonymous Passenger',
        'ticketNumber': auth.currentUser?.ticketNumber,
        'busNumber': auth.currentUser?.busNumber,
        'routeName': auth.currentUser?.routeName,
        'phoneNumber': auth.currentUser?.phoneNumber, // Add phone for better identification
        'complaint': _complaintController.text.trim(),
        'status': 'pending',
        'source': 'mobile',
        'companyId': 'COMPANY_001',
        'createdAt': FieldValue.serverTimestamp(),
        // Additional context for better complaint tracking
        'passengerEmail': auth.currentUser?.email, // Keep the generated email for reference
        'origin': auth.currentUser?.origin,
        'destination': auth.currentUser?.destination,
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
              // Show passenger info for context
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reporting as: ${context.read<AuthService>().currentUser?.passengerName ?? 'Anonymous'}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (context.read<AuthService>().currentUser?.ticketNumber != null)
                      Text('Ticket: ${context.read<AuthService>().currentUser!.ticketNumber}'),
                    if (context.read<AuthService>().currentUser?.busNumber != null)
                      Text('Bus: ${context.read<AuthService>().currentUser!.busNumber}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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

  void _showTicketInfoDialog() {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.confirmation_number, color: Colors.green),
            SizedBox(width: 8),
            Text('Your Ticket'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user?.passengerName != null) ...[
              Text('Passenger: ${user!.passengerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
            ],
            if (user?.ticketNumber != null) ...[
              Text('Ticket: ${user!.ticketNumber}'),
              const SizedBox(height: 8),
            ],
            if (user?.phoneNumber != null) ...[
              Text('Phone: ${user!.phoneNumber}'),
              const SizedBox(height: 8),
            ],
            if (user?.routeName != null) ...[
              Text('Route: ${user!.routeName}'),
              const SizedBox(height: 8),
            ],
            if (user?.origin != null && user?.destination != null) ...[
              Text('${user!.origin} → ${user.destination}'),
              const SizedBox(height: 8),
            ],
            if (user?.busNumber != null) ...[
              Text('Bus: ${user!.busNumber}'),
              const SizedBox(height: 8),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 8),
            Text('Confirm Logout'),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout? Your trip tracking will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop(); // Close dialog
              await _performLogout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Logging out...'),
                ],
              ),
            ),
          ),
        ),
      );

      final auth = context.read<AuthService>();
      final locationService = context.read<LocationService>();
      final monitoring = context.read<MonitoringService>();

      // Stop location tracking
      locationService.stopLocationTracking();
      _locationUpdateTimer?.cancel();

      // Stop monitoring services
      if (auth.currentUser?.busNumber != null) {
        monitoring.stopMonitoring(auth.currentUser!.busNumber!);
      } else {
        // If no specific bus, try to stop general monitoring
        try {
          monitoring.stopMonitoring('');
        } catch (e) {
          debugPrint('Error stopping monitoring: $e');
        }
      }

      // Clean up passenger location from database
      if (auth.currentUser != null) {
        try {
          await FirebaseFirestore.instance
              .collection('passenger_locations')
              .doc(auth.currentUser!.id)
              .update({
            'isActive': false,
            'lastUpdate': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Error updating passenger status on logout: $e');
        }
      }

      // Perform logout
      await auth.logout();

      // Navigate back to login selection
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/', 
          (route) => false,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logged out successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        title: Text('${auth.currentUser?.passengerName ?? 'Passenger'} - ${auth.currentUser?.routeName ?? 'Your Trip'}'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          // Ticket info button
          IconButton(
            icon: const Icon(Icons.confirmation_number),
            onPressed: _showTicketInfoDialog,
            tooltip: 'View Ticket Details',
          ),
          IconButton(
            icon: const Icon(Icons.warning),
            onPressed: _showComplaintDialog,
            tooltip: 'Report Issue',
          ),
          IconButton(
            icon: const Icon(Icons.emergency),
            onPressed: _showEmergencyDialog,
            color: Colors.red,
            tooltip: 'Emergency',
          ),
          // NEW: Logout button
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (String value) {
              if (value == 'logout') {
                _showLogoutDialog();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Enhanced Trip Info Card
          Card(
            margin: const EdgeInsets.all(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Passenger info row
                  if (auth.currentUser?.passengerName != null)
                    Row(
                      children: [
                        const Icon(Icons.person, size: 20, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'Welcome, ${auth.currentUser!.passengerName}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  
                  // Trip details
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (auth.currentUser?.busNumber != null)
                              Row(
                                children: [
                                  const Icon(Icons.directions_bus, size: 16, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text('Bus: ${auth.currentUser!.busNumber}'),
                                ],
                              ),
                            const SizedBox(height: 4),
                            if (auth.currentUser?.routeName != null)
                              Row(
                                children: [
                                  const Icon(Icons.route, size: 16, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text('Route: ${auth.currentUser!.routeName}')),
                                ],
                              ),
                            const SizedBox(height: 4),
                            if (auth.currentUser?.origin != null && auth.currentUser?.destination != null)
                              Row(
                                children: [
                                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text('${auth.currentUser!.origin} → ${auth.currentUser!.destination}')),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (auth.currentUser?.ticketNumber != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Text(
                            auth.currentUser!.ticketNumber!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Map section
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Emergency FAB
          FloatingActionButton(
            heroTag: "emergency",
            onPressed: _showEmergencyDialog,
            backgroundColor: Colors.red,
            child: const Icon(Icons.emergency, color: Colors.white),
          ),
          const SizedBox(height: 16),
          // Location FAB
          FloatingActionButton(
            heroTag: "location",
            onPressed: _centerMapOnMyLocation,
            backgroundColor: Colors.green,
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
    );
  }
}