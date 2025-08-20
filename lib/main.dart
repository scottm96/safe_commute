import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'driver_screen.dart';
import 'passenger_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: const SafeCommuteApp(),
    ),
  );
}

class SafeCommuteApp extends StatelessWidget {
  const SafeCommuteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Transport Monitoring',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailOrTicketController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isDriver = true;

  Future<void> _handleLogin(AuthService authService) async {
    if (!_formKey.currentState!.validate()) return;

    bool success = false;

    if (_isDriver) {
      success = await authService.loginDriver(
        _emailOrTicketController.text.trim(),
        _passwordController.text.trim(),
      );
    } else {
      success = await authService.loginPassenger(
        _emailOrTicketController.text.trim(),
      );
    }

    if (success && mounted) {
      if (_isDriver) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PassengerScreen()),
        );
      }
    } else if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authService.errorMessage ?? 'Login failed. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                SwitchListTile(
                  title: Text(_isDriver ? 'Driver Login' : 'Passenger Login'),
                  value: _isDriver,
                  onChanged: (val) {
                    setState(() {
                      _isDriver = val;
                      _emailOrTicketController.clear();
                      _passwordController.clear();
                    });
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailOrTicketController,
                  decoration: InputDecoration(
                    labelText: _isDriver ? 'Email' : 'Ticket Number',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return _isDriver
                          ? 'Please enter your email'
                          : 'Please enter your ticket number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                if (_isDriver)
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (_isDriver &&
                          (value == null || value.isEmpty)) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: authService.isLoading
                      ? null
                      : () => _handleLogin(authService),
                  child: authService.isLoading
                      ? const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        )
                      : const Text('Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
