import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'monitoring_service.dart';
import 'location_service.dart';

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  bool _isStreamingImages = false;
  bool _cameraInitialized = false;
  Timer? _eyeClosureTimer;
  int _closedEyeFrames = 0;
  bool _alertTriggered = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _alertEscalationTimer;
  //Timer? _autoStopTimer;
  Timer? _locationUpdateTimer;
  String? _currentScheduleId;

 /* final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };*/

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFaceDetector();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCamera();
      _startLocationTracking();
      _checkForAssignedSchedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopDetection();
    } else if (state == AppLifecycleState.resumed) {
      if (!_cameraInitialized) {
        _initializeCamera();
      }
    }
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.fast,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _initializeCamera() async {
    try {
      debugPrint("Initializing camera...");
      cameras = await availableCameras();
      if (cameras == null || cameras!.isEmpty) {
        debugPrint("No cameras available");
        return;
      }
      
      final frontCamera = cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras!.first,
      );

      _controller = CameraController(frontCamera, ResolutionPreset.medium);
      await _controller!.initialize();
      _cameraInitialized = true;
      if (mounted) setState(() {});
      debugPrint("Camera initialized successfully");
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

  void _startDetection() {
    if (!_cameraInitialized || _isStreamingImages) return;

    _isStreamingImages = true;
    _closedEyeFrames = 0;
    _alertTriggered = false;
    _eyeClosureTimer?.cancel();

    _processImageStream();
    setState(() {});
  }

  void _stopDetection() {
    _isStreamingImages = false;
    _eyeClosureTimer?.cancel();
    _alertEscalationTimer?.cancel();
    _audioPlayer.stop();
    Vibration.cancel();
    setState(() {});
  }

  void _processImageStream() async {
    if (!_controller!.value.isInitialized) return;

    final image = await _controller!.takePicture();
    final inputImage = InputImage.fromFilePath(image.path);

    try {
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        final eyeOpenProbability = face.smilingProbability ?? 0.0;

        if (eyeOpenProbability < 0.3) {
          _closedEyeFrames++;
          _eyeClosureTimer ??= Timer(const Duration(seconds: 3), () {
            if (_closedEyeFrames >= 90) { // ~3 seconds at 30fps
              _triggerAlert();
            }
          });
        } else {
          _closedEyeFrames = 0;
          _eyeClosureTimer?.cancel();
        }
      }
    } catch (e) {
      debugPrint('Face detection error: $e');
    }

    if (_isStreamingImages) {
      Future.delayed(const Duration(milliseconds: 33), _processImageStream); // ~30fps
    }
  }

  void _triggerAlert() async {
    if (_alertTriggered) return;
    _alertTriggered = true;

    // Play alarm
    await _audioPlayer.play(AssetSource('sounds/alarm.wav'));
    Vibration.vibrate(pattern: [500, 1000, 500, 1000]);

    // Escalate if not acknowledged
    _alertEscalationTimer = Timer(const Duration(seconds: 10), () {
      _escalateAlert();
    });

    // Log incident
    final monitoring = Provider.of<MonitoringService>(context, listen: false);
    final auth = Provider.of<AuthService>(context, listen: false);
    monitoring.logIncident(auth.currentUser!.id, 'DROWSINESS_SEVERE', 'Driver drowsiness detected');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ALERT: Eyes closed detected! Please focus on road.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _escalateAlert() async {
    // TODO: Send emergency notification
    debugPrint('Escalating alert to control center');
  }

  Future<void> _startLocationTracking() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    await locationService.startLocationTracking(
      onLocationUpdate: (position) => _updateDriverLocation(position),
    );

    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      final position = await locationService.getCurrentLocation();
      if (position != null) {
        _updateDriverLocation(position);
      }
    });
  }

  Future<void> _updateDriverLocation(Position position) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final monitoring = Provider.of<MonitoringService>(context, listen: false);
    if (auth.currentUser == null) return;

    final status = DriverStatus(
      driverId: auth.currentUser!.id,
      busNumber: auth.currentUser!.busNumber ?? '',
      location: position,
      lastUpdate: DateTime.now(),
      isDrowsy: _closedEyeFrames > 0,
      closedEyeFrames: _closedEyeFrames,
    );

    await monitoring.updateDriverStatus(status);
  }

  Future<void> _checkForAssignedSchedule() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final query = await FirebaseFirestore.instance
        .collection('schedules')
        .where('busNumber', isEqualTo: auth.currentUser!.busNumber)
        .where('status', isEqualTo: 'scheduled')
        .where('companyId', isEqualTo: 'COMPANY_001')
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      _currentScheduleId = query.docs.first.id;
      debugPrint('Assigned schedule found: $_currentScheduleId');
    }
  }

  Future<void> _startTrip() async {
    if (_currentScheduleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No assigned schedule')));
      return;
    }

    final location = await Geolocator.getCurrentPosition();
    final monitoring = Provider.of<MonitoringService>(context, listen: false);
    final auth = Provider.of<AuthService>(context, listen: false);

    await monitoring.logTripStart(_currentScheduleId!, auth.currentUser!.id, {
      'latitude': location.latitude,
      'longitude': location.longitude,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip started! Departure logged.'), backgroundColor: Colors.green),
    );
  }

  Future<void> _endTrip() async {
    if (_currentScheduleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active trip')));
      return;
    }

    final location = await Geolocator.getCurrentPosition();
    final monitoring = Provider.of<MonitoringService>(context, listen: false);
    final auth = Provider.of<AuthService>(context, listen: false);

    await monitoring.logTripEnd(_currentScheduleId!, auth.currentUser!.id, {
      'latitude': location.latitude,
      'longitude': location.longitude,
    });

    _currentScheduleId = null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip ended! Arrival logged.'), backgroundColor: Colors.green),
    );
  }

  @override
  void dispose() {
    _stopDetection();
    _locationUpdateTimer?.cancel();
    _controller?.dispose();
    _faceDetector.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // For keepAlive
    final location = Provider.of<LocationService>(context);
    final auth = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Driver Dashboard - Bus ${auth.currentUser?.busNumber ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
          ),
        ],
      ),
      body: _cameraInitialized && _controller!.value.isInitialized
          ? Column(
              children: [
                // Camera Preview
                Expanded(
                  flex: 3,
                  child: CameraPreview(_controller!),
                ),
                // Status Bar
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black87,
                  child: Row(
                    children: [
                      if (_closedEyeFrames > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Eyes Closed: $_closedEyeFrames frames',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      const Spacer(),
                      if (location.currentPosition != null)
                        Text(
                          'Speed: ${(location.currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                    ],
                  ),
                ),
                // Control buttons
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (!_isDetecting && !_isStreamingImages && _cameraInitialized)
                              ? _startDetection
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(_isStreamingImages
                              ? 'Detection Active'
                              : 'Start Detection'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isStreamingImages ? Colors.green : Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isStreamingImages ? _stopDetection : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop Detection'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Trip Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _currentScheduleId != null ? _startTrip : null,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start Trip'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        ),
                      ),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _currentScheduleId != null ? _endTrip : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('End Trip'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}