import 'package:flutter/material.dart';
import 'package:safe_commute/driver_screen.dart';
import 'package:safe_commute/passenger_screen.dart';

void main() {
  runApp(SafeCommuteApp());
}

class SafeCommuteApp extends StatelessWidget {
  const SafeCommuteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ModeSelectionScreen(),
    );
  }
}

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SafeCommute')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DriverScreen())), // Placeholder for navigation
              child: Text('Driver Mode'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassengerScreen())), // Placeholder for navigation
              child: Text('Passenger Mode'),
            ),
          ],
        ),
      ),
    );
  }
}