import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'auth_service.dart';
import 'user_type.dart';

class RouteSelectionScreen extends StatefulWidget {
  const RouteSelectionScreen({super.key});

  @override
  State<RouteSelectionScreen> createState() => _RouteSelectionScreenState();
}

class _RouteSelectionScreenState extends State<RouteSelectionScreen> {
  String? _selectedRouteId;
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _schedules = [];
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('routes')
          .where('isActive', isEqualTo: true)
          .where('companyId', isEqualTo: 'COMPANY_001')
          .get();
      setState(() {
        _routes = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading routes: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSchedules(String routeId) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schedules')
          .where('routeId', isEqualTo: routeId)
          .where('departureTime', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
          .where('departureTime', isLessThan: Timestamp.fromDate(tomorrow))
          .where('status', isEqualTo: 'scheduled')
          .where('companyId', isEqualTo: 'COMPANY_001')
          .get();
      setState(() {
        _schedules = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      });
    } catch (e) {
      debugPrint('Error loading schedules: $e');
    }
  }

  Future<void> _bookTicket(String scheduleId, Map<String, dynamic> schedule) async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter name and phone')));
      return;
    }

    try {
      final routeDoc = await FirebaseFirestore.instance.collection('routes').doc(_selectedRouteId).get();
      if (!routeDoc.exists) return;
      final routeData = routeDoc.data()!;

      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final query = await FirebaseFirestore.instance
          .collection('tickets')
          .where('ticketNumber', isGreaterThanOrEqualTo: 'TKT-$dateStr-0000')
          .where('ticketNumber', isLessThanOrEqualTo: 'TKT-$dateStr-9999')
          .get();
      final count = query.docs.length;
      final ticketNumber = 'TKT-$dateStr-${(count + 1).toString().padLeft(4, '0')}';

      await FirebaseFirestore.instance.collection('tickets').add({
        'ticketNumber': ticketNumber,
        'passengerName': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'routeId': _selectedRouteId,
        'routeName': routeData['name'],
        'busNumber': schedule['busNumber'] ?? 'TBA',
        'departureTime': schedule['departureTime'],
        'fare': routeData['fare'],
        'isUsed': false,
        'currentSession': null,
        'origin': routeData['origin'],
        'destination': routeData['destination'],
        'companyId': 'COMPANY_001',
        'createdAt': FieldValue.serverTimestamp(),
        // Add 24-hour expiration from booking time
        'expiresAt': Timestamp.fromDate(DateTime.now().add(Duration(hours: 24))),
      });

      // Generate and print PDF
      final pdf = await _generateTicketPdf(ticketNumber, _nameController.text.trim(), routeData, schedule);
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => await pdf.save());

      // Show success message with ticket number
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ticket booked successfully! Your ticket number is: $ticketNumber'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );

        // Show dialog with ticket details and instructions
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Ticket Booked Successfully!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Ticket Number:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        ticketNumber,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Important Instructions:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('• Save your ticket number safely'),
                const Text('• Use this number to login to the passenger app'),
                const Text('• Your ticket is valid for 24 hours after booking'),
                const Text('• Present your ticket to the conductor when boarding'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ticket expires 24 hours after booking',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  // Navigate back to passenger login screen
                  Navigator.pushReplacementNamed(context, '/login/passenger');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Login with Ticket'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<pw.Document> _generateTicketPdf(String ticketNumber, String name, Map<String, dynamic> route, Map<String, dynamic> schedule) async {
    final pdf = pw.Document();
    final departure = (schedule['departureTime'] as Timestamp).toDate();
    final expiryTime = DateTime.now().add(Duration(hours: 24)); // Add expiry time
    final qrPainter = QrPainter(data: ticketNumber, version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.H);
    final byteData = await qrPainter.toImageData(200);
    final qrImage = byteData != null ? pw.MemoryImage(byteData.buffer.asUint8List()) : null;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Header(level: 0, child: pw.Text('Ghana InterCity Trans E-Ticket', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 20),
            pw.Text('Ticket Number: $ticketNumber', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('Passenger: $name'),
            pw.SizedBox(height: 10),
            pw.Text('Route: ${route['name']} (${route['origin']} → ${route['destination']})'),
            pw.SizedBox(height: 10),
            pw.Text('Bus: ${schedule['busNumber'] ?? 'TBA'}'),
            pw.SizedBox(height: 10),
            pw.Text('Departure: ${departure.toLocal().toString().substring(0, 16)}'),
            pw.SizedBox(height: 10),
            pw.Text('Fare: GH₵${route['fare']}'),
            pw.SizedBox(height: 10),
            // Add expiry information to PDF
            pw.Text('Ticket Expires: ${expiryTime.toString().substring(0, 16)}', style: pw.TextStyle(fontSize: 12, color: const PdfColor.fromInt(0xFFFF6B00))),
            pw.SizedBox(height: 20),
            if (qrImage != null)
              pw.Container(height: 100, child: pw.Image(qrImage)),
            pw.Text('Scan QR for boarding. Valid for COMPANY_001 only.', style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic)),
            pw.SizedBox(height: 10),
            pw.Text('Ticket valid for 24 hours from booking time.', style: pw.TextStyle(fontSize: 10, color: const PdfColor.fromInt(0xFF666666))),
          ],
        ),
      ),
    );
    return pdf;
  }

  Widget _buildRouteDropdownItem(Map<String, dynamic> route) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            route['name'] ?? 'Unknown Route',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${route['origin'] ?? ''} → ${route['destination'] ?? ''}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'GH₵${route['fare'] ?? 0}',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedRouteDisplay(Map<String, dynamic>? route) {
    if (route == null) return const Text('Select Route');
    
    return Text(
      route['name'] ?? 'Unknown Route',
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Your Trip'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Route Selection Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Your Route',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedRouteId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Choose Route',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                            selectedItemBuilder: (BuildContext context) {
                              return _routes.map<Widget>((route) {
                                return _buildSelectedRouteDisplay(route);
                              }).toList();
                            },
                            items: _routes.map<DropdownMenuItem<String>>((route) {
                              return DropdownMenuItem<String>(
                                value: route['id'] as String,
                                child: _buildRouteDropdownItem(route),
                              );
                            }).toList(),
                            onChanged: (id) {
                              setState(() {
                                _selectedRouteId = id;
                                _schedules.clear();
                              });
                              if (id != null) _loadSchedules(id);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Schedules Section
                  if (_selectedRouteId != null) ...[
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Available Departures Today',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_schedules.isEmpty) 
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.schedule,
                                        size: 48,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'No available departures today',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Please check back tomorrow or select a different route',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _schedules.length,
                                itemBuilder: (context, index) {
                                  final schedule = _schedules[index];
                                  final departure = (schedule['departureTime'] as Timestamp).toDate().toLocal();
                                  
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      leading: const CircleAvatar(
                                        backgroundColor: Colors.green,
                                        child: Icon(
                                          Icons.directions_bus,
                                          color: Colors.white,
                                        ),
                                      ),
                                      title: Text(
                                        'Bus: ${schedule['busNumber'] ?? 'Unassigned'}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Text('Departs: ${departure.toString().substring(11, 16)}'),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Text(departure.toString().substring(0, 10)),
                                            ],
                                          ),
                                        ],
                                      ),
                                      trailing: ElevatedButton(
                                        onPressed: () => _showBookingDialog(schedule),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Book'),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.route,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Select a route to view available departures',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  void _showBookingDialog(Map<String, dynamic> schedule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.confirmation_number, color: Colors.green),
            SizedBox(width: 8),
            Text('Confirm Booking'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Booking Summary:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Bus: ${schedule['busNumber'] ?? 'TBA'}'),
                    Text('Route: ${schedule['routeName'] ?? 'Selected Route'}'),
                    Text('Departure: ${(schedule['departureTime'] as Timestamp).toDate().toLocal().toString().substring(0, 16)}'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Ticket valid for 24 hours after booking',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _bookTicket(schedule['id'], schedule);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Book & Print'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}