import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'user_type.dart';
import 'route_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  final UserType userType;

  const LoginScreen({super.key, required this.userType});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controllers for different login types
  TextEditingController? _emailController;
  TextEditingController? _passwordController;
  TextEditingController? _ticketController;
  
  // State for passenger options
  bool _showTicketLogin = false;
  Map<String, dynamic>? _ticketInfo;
  bool _isCheckingTicket = false;
  String? _ticketError;

  @override
  void initState() {
    super.initState();
    if (widget.userType == UserType.driver) {
      _emailController = TextEditingController();
      _passwordController = TextEditingController();
    } else {
      _ticketController = TextEditingController();
      // Start with passenger options (not ticket login)
      _showTicketLogin = false;
    }
  }

  Future<void> _loginDriver() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    if (_emailController!.text.trim().isEmpty || _passwordController!.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields")),
      );
      return;
    }

    final success = await authService.loginDriver(
      _emailController!.text.trim(),
      _passwordController!.text.trim(),
    );

    if (success && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    } else if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authService.errorMessage ?? "Login failed")),
      );
    }
  }

  Future<void> _checkTicket() async {
    if (_ticketController!.text.trim().isEmpty) {
      setState(() => _ticketError = 'Please enter a ticket number');
      return;
    }

    setState(() {
      _isCheckingTicket = true;
      _ticketError = null;
    });

    final auth = Provider.of<AuthService>(context, listen: false);
    
    try {
      final ticketInfo = await auth.getTicketInfo(_ticketController!.text.trim());
      
      if (ticketInfo == null) {
        setState(() {
          _ticketError = 'Ticket not found. Please check your ticket number.';
          _ticketInfo = null;
        });
      } else {
        setState(() => _ticketInfo = ticketInfo);
      }
    } catch (e) {
      setState(() {
        _ticketError = 'Error checking ticket: ${e.toString()}';
        _ticketInfo = null;
      });
    } finally {
      setState(() => _isCheckingTicket = false);
    }
  }

  Future<void> _loginWithTicket() async {
    setState(() {
      _isCheckingTicket = true;
      _ticketError = null;
    });

    final auth = Provider.of<AuthService>(context, listen: false);
    
    try {
      final success = await auth.loginPassenger(_ticketController!.text.trim());
      
      if (success && mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
      } else if (!success && mounted) {
        setState(() => _ticketError = auth.errorMessage ?? 'Login failed');
      }
    } catch (e) {
      setState(() => _ticketError = 'Login error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isCheckingTicket = false);
    }
  }

  void _navigateToRouteSelection() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RouteSelectionScreen()),
    );
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
    // Debug print to check the state
    debugPrint('UserType: ${widget.userType}, ShowTicketLogin: $_showTicketLogin');
    
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
                          : _showTicketLogin
                              ? Icons.confirmation_number
                              : Icons.person,
                        size: 64,
                        color: widget.userType == UserType.driver 
                          ? Colors.blue 
                          : Colors.green,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.userType == UserType.driver 
                            ? 'Driver Login' 
                            : _showTicketLogin 
                                ? 'Ticket Login' 
                                : 'Passenger Access',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      
                      // Driver Login Form
                      if (widget.userType == UserType.driver) ..._buildDriverLogin()
                      
                      // Passenger Options (when not showing ticket login)
                      else if (!_showTicketLogin) ..._buildPassengerOptions()
                      
                      // Ticket Login Form
                      else ..._buildTicketLogin(),
                      
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

  List<Widget> _buildDriverLogin() {
    return [
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
      const SizedBox(height: 24),
      Consumer<AuthService>(
        builder: (context, authService, child) {
          return SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: authService.isLoading ? null : _loginDriver,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
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
                  : const Text("Login", style: TextStyle(fontSize: 16)),
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _buildPassengerOptions() {
    return [
      const Text(
        'Choose how to access the app:',
        style: TextStyle(fontSize: 16),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      
      // Book New Ticket Option
      SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton.icon(
          onPressed: _navigateToRouteSelection,
          icon: const Icon(Icons.add_shopping_cart, size: 24),
          label: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Book New Ticket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Purchase ticket and board', style: TextStyle(fontSize: 12)),
            ],
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ),
      
      const SizedBox(height: 16),
      
      // Login with Existing Ticket Option
      SizedBox(
        width: double.infinity,
        height: 60,
        child: OutlinedButton.icon(
          onPressed: () {
            debugPrint('Switching to ticket login');
            setState(() => _showTicketLogin = true);
          },
          icon: const Icon(Icons.confirmation_number, size: 24),
          label: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Use Existing Ticket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Already have a ticket number', style: TextStyle(fontSize: 12)),
            ],
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.green,
            side: const BorderSide(color: Colors.green, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildTicketLogin() {
    return [
      Text(
        'Enter the ticket number you received when booking online',
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _ticketController,
        decoration: InputDecoration(
          labelText: "Ticket Number",
          hintText: "TKT-20241201-0001",
          prefixIcon: const Icon(Icons.qr_code),
          border: const OutlineInputBorder(),
          errorText: _ticketError,
        ),
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (_) => _ticketInfo == null ? _checkTicket() : _loginWithTicket(),
      ),
      
      const SizedBox(height: 16),
      
      // Ticket Preview (if ticket found)
      if (_ticketInfo != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Ticket Found!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              if (_ticketInfo!['passengerName'] != null) ...[
                Text('Passenger: ${_ticketInfo!['passengerName']}'),
                const SizedBox(height: 4),
              ],
              
              if (_ticketInfo!['routeName'] != null) ...[
                Text('Route: ${_ticketInfo!['routeName']}'),
                const SizedBox(height: 4),
              ],
              
              if (_ticketInfo!['busNumber'] != null) ...[
                Text('Bus: ${_ticketInfo!['busNumber']}'),
                const SizedBox(height: 4),
              ],
              
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _ticketInfo!['currentSession'] != null 
                      ? Colors.orange.shade100 
                      : _ticketInfo!['isUsed'] == true 
                          ? Colors.red.shade100 
                          : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _ticketInfo!['currentSession'] != null 
                      ? 'In Use' 
                      : _ticketInfo!['isUsed'] == true 
                          ? 'Used' 
                          : 'Valid',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _ticketInfo!['currentSession'] != null 
                        ? Colors.orange.shade700 
                        : _ticketInfo!['isUsed'] == true 
                            ? Colors.red.shade700 
                            : Colors.green.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      
      const SizedBox(height: 8),
      
      // Action Button
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _isCheckingTicket 
              ? null 
              : _ticketInfo == null 
                  ? _checkTicket 
                  : _loginWithTicket,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isCheckingTicket
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _ticketInfo == null ? "Check Ticket" : "Login with Ticket",
                  style: const TextStyle(fontSize: 16),
                ),
        ),
      ),
      
      const SizedBox(height: 12),
      TextButton(
        onPressed: () {
          debugPrint('Going back to passenger options');
          setState(() {
            _showTicketLogin = false;
            _ticketInfo = null;
            _ticketError = null;
          });
          _ticketController!.clear();
        },
        child: const Text("Back to options"),
      ),
      
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            const Text(
              'Need Help?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your ticket number looks like "TKT-20241201-0001"',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ];
  }
}