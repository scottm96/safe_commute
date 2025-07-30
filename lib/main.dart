import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';




void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Init Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AuthCheckScreen(),
    );
  }
}

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreeenState();
}

class _AuthCheckScreeenState extends State<AuthCheckScreen> {
  String _authStatus = 'Checking Firebase Authentication...';

  @override
  void initState() {
    super.initState();
    _performAnonymousLogin();
  }

  Future<void> _performAnonymousLogin() async {
    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      if (userCredential.user != null) {
        setState(() {
          _authStatus = 'Firebase initialized and Anonymous login successful! User ID: ${userCredential.user!.uid}';
        });
      } else {
        setState(() {
          _authStatus = 'Anonymous login failed: User is null.';
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _authStatus = 'Firebase Auth Error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _authStatus = 'General Error during anonymous login: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Initialization Test'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _authStatus,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}