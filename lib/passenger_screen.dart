import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'monitoring_service.dart';
//import 'location_service.dart';

class PassengerScreen extends StatefulWidget {
  const PassengerScreen({super.key});

  @override
  State<PassengerScreen> createState() => _PassengerScreenState();
}

class _PassengerScreenState extends State<PassengerScreen> {
  @override
  void initState() {
    super.initState();
    // Start monitoring all drivers for passenger safety info
    context.read<MonitoringService>().startMonitoringAllDrivers();
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  Color _getAlertColor(DriverAlertLevel alertLevel) {
    switch (alertLevel) {
      case DriverAlertLevel.none:
        return Colors.green;
      case DriverAlertLevel.mild:
        return Colors.yellow;
      case DriverAlertLevel.moderate:
        return Colors.orange;
      case DriverAlertLevel.severe:
        return Colors.red;
    }
  }

  String _getAlertText(DriverAlertLevel alertLevel) {
    switch (alertLevel) {
      case DriverAlertLevel.none:
        return 'Driver Alert';
      case DriverAlertLevel.mild:
        return 'Driver Slightly Tired';
      case DriverAlertLevel.moderate:
        return 'Driver Moderately Tired';
      case DriverAlertLevel.severe:
        return 'Driver Very Tired - Caution!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passenger Mode'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          Consumer<AuthService>(
            builder: (context, auth, _) {
              return PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'logout') {
                    _logout();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'info',
                    child: ListTile(
                      leading: const Icon(Icons.confirmation_number),
                      title: const Text('Passenger'),
                      subtitle: Text('Ticket: ${auth.currentUser?.ticketNumber ?? 'Unknown'}'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('Logout'),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<MonitoringService>(
        builder: (context, monitoring, _) {
          // Find current bus driver (this would need to be enhanced with route matching)
          final currentDriver = monitoring.allDrivers.isNotEmpty 
              ? monitoring.allDrivers.first 
              : null;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome card
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 48,
                          color: Colors.green[600],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Welcome Passenger!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Consumer<AuthService>(
                          builder: (context, auth, _) {
                            return Text(
                              'Ticket: ${auth.currentUser?.ticketNumber ?? 'Unknown'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),

                // Current trip status
                const Text(
                  'Current Trip Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                if (currentDriver != null) ...[
                  // Driver status card
                  Card(
                    elevation: 4,
                    color: _getAlertColor(currentDriver.alertLevel).withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.drive_eta,
                                color: _getAlertColor(currentDriver.alertLevel),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Bus ${currentDriver.busNumber}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      _getAlertText(currentDriver.alertLevel),
                                      style: TextStyle(
                                        color: _getAlertColor(currentDriver.alertLevel),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: currentDriver.isOnline ? Colors.green : Colors.red,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  currentDriver.isOnline ? 'Online' : 'Offline',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          if (currentDriver.location != null) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  'Speed: ${(currentDriver.location!.speed * 3.6).toStringAsFixed(1)} km/h',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(width: 16),
                                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  'Updated: ${_formatTime(currentDriver.lastUpdate)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],

                          if (currentDriver.alertLevel != DriverAlertLevel.none) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _getAlertColor(currentDriver.alertLevel).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _getAlertColor(currentDriver.alertLevel),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning,
                                    color: _getAlertColor(currentDriver.alertLevel),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      currentDriver.alertLevel == DriverAlertLevel.severe
                                          ? 'Driver is showing signs of severe fatigue. Please remain alert and consider notifying transport authorities if concerned.'
                                          : 'Driver is showing mild signs of fatigue but is still safe to drive.',
                                      style: TextStyle(
                                        color: _getAlertColor(currentDriver.alertLevel),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 48,
                            color: Colors.orange[600],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No Active Driver Found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Unable to locate your driver at the moment. Please ensure you are on the correct vehicle.',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Safety features
                const Text(
                  'Safety Features',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                _buildSafetyFeatureCard(
                  'Drowsiness Detection',
                  'Monitors driver alertness in real-time',
                  Icons.remove_red_eye,
                  Colors.blue,
                ),
                const SizedBox(height: 12),

                _buildSafetyFeatureCard(
                  'Location Tracking',
                  'Tracks vehicle location for safety',
                  Icons.location_on,
                  Colors.green,
                ),
                const SizedBox(height: 12),

                _buildSafetyFeatureCard(
                  'HQ Monitoring',
                  'Transport headquarters monitors this trip',
                  Icons.security,
                  Colors.purple,
                ),

                const SizedBox(height: 20),

                // Emergency contact (placeholder)
                Card(
                  elevation: 4,
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.emergency,
                          size: 48,
                          color: Colors.red[600],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Emergency Contact',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'In case of emergency, contact:\nTransport Authority: +233-XXX-XXXX',
                          style: TextStyle(color: Colors.grey[700]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            // Implement emergency contact functionality
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Emergency contact feature coming soon'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.phone),
                          label: const Text('Call Emergency'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSafetyFeatureCard(String title, String description, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(description),
        trailing: Icon(
          Icons.check_circle,
          color: Colors.green[600],
          size: 20,
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}