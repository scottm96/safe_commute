import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'user_type.dart';

class LoginScreen extends StatefulWidget {
  final UserType userType;

  const LoginScreen({super.key, required this.userType});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Only create the controllers you need
  TextEditingController? _emailController;
  TextEditingController? _passwordController;
  TextEditingController? _ticketController;

  @override
  void initState() {
    super.initState();
    if (widget.userType == UserType.driver) {
      _emailController = TextEditingController();
      _passwordController = TextEditingController();
    } else {
      _ticketController = TextEditingController();
    }
  }

  Future<void> _login(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);

    bool success = false;
    
    if (widget.userType == UserType.driver) {
      if (_emailController!.text.trim().isEmpty || _passwordController!.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please fill in all fields")),
        );
        return;
      }
      success = await authService.loginDriver(
        _emailController!.text.trim(),
        _passwordController!.text.trim(),
      );
    } else {
      if (_ticketController!.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter your ticket number")),
        );
        return;
      }
      success = await authService.loginPassenger(
        _ticketController!.text.trim(),
      );
    }

    if (success && mounted) {
      // Navigate back to the AuthWrapper, which will automatically redirect to the appropriate screen
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/auth', 
        (route) => false, // Remove all previous routes
      );
    } else if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authService.errorMessage ?? "Login failed")),
      );
    }
  }

  @override
  void dispose() {
    _emailController?.dispose();
    _passwordController?.dispose();
    _ticketController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.userType == UserType.driver 
              ? [Colors.blue, Colors.blueAccent]
              : [Colors.green, Colors.greenAccent],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.userType == UserType.driver 
                          ? Icons.drive_eta 
                          : Icons.person,
                        size: 64,
                        color: widget.userType == UserType.driver 
                          ? Colors.blue 
                          : Colors.green,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.userType == UserType.driver
                            ? "Driver Login"
                            : "Passenger Login",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      if (widget.userType == UserType.driver) ...[
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: "Email",
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "Password",
                            prefixIcon: Icon(Icons.lock),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _ticketController,
                          decoration: const InputDecoration(
                            labelText: "Ticket Number",
                            prefixIcon: Icon(Icons.confirmation_number),
                            border: OutlineInputBorder(),
                            hintText: "TKT-XXXXXXXX-XXXX",
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ],
                      
                      const SizedBox(height: 24),
                      
                      Consumer<AuthService>(
                        builder: (context, authService, child) {
                          return SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: authService.isLoading 
                                ? null 
                                : () => _login(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: widget.userType == UserType.driver 
                                  ? Colors.blue 
                                  : Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: authService.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    "Login",
                                    style: TextStyle(fontSize: 16),
                                  ),
                            ),
                          );
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Back to selection"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}