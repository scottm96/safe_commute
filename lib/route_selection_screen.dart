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
      });

      // Generate and print PDF
      final pdf = await _generateTicketPdf(ticketNumber, _nameController.text.trim(), routeData, schedule);
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => await pdf.save());

      // Auto-login
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.loginPassenger(ticketNumber);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/auth');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking failed: $e')));
    }
  }

  Future<pw.Document> _generateTicketPdf(String ticketNumber, String name, Map<String, dynamic> route, Map<String, dynamic> schedule) async {
    final pdf = pw.Document();
    final departure = (schedule['departureTime'] as Timestamp).toDate();
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
            pw.SizedBox(height: 20),
            if (qrImage != null)
              pw.Container(height: 100, child: pw.Image(qrImage)),
            pw.Text('Scan QR for boarding. Valid for COMPANY_001 only.', style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic)),
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