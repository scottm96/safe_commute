import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
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
  Timer? _autoStopTimer;
  Timer? _locationUpdateTimer;

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  bool get wantKeepAlive => true; // Keep widget alive

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFaceDetector();
    
    // Delay camera initialization to ensure proper widget mounting
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCamera();
      _startLocationTracking();
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
      // Re-initialize camera if needed
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

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium, // Changed from low to medium for better detection
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.yuv420 
            : ImageFormatGroup.bgra8888,
        enableAudio: false,
      );
      
      await _controller!.initialize();
      _cameraInitialized = true;
      
      if (mounted) {
        setState(() {});
        debugPrint("Camera initialized successfully");
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
      _cameraInitialized = false;
      // Retry initialization after a delay
      Timer(const Duration(seconds: 2), () {
        if (mounted && !_cameraInitialized) {
          _initializeCamera();
        }
      });
    }
  }

  void _startLocationTracking() async {
    final locationService = context.read<LocationService>();
    final monitoringService = context.read<MonitoringService>();
    final auth = context.read<AuthService>();

    if (auth.currentUser != null) {
      // Start monitoring service
      await monitoringService.startDriverMonitoring(
        auth.currentUser!.id,
        auth.currentUser!.busNumber ?? 'Unknown',
      );

      // Start location tracking with proper error handling
      bool locationStarted = await locationService.startLocationTracking(
        onLocationUpdate: (Position position) {
          // Update location in monitoring service
          monitoringService.updateDriverLocation(
              auth.currentUser!.id, position);
        },
      );

      if (locationStarted) {
        debugPrint("Location tracking started successfully");
        // Start periodic location updates
        _locationUpdateTimer =
            Timer.periodic(const Duration(seconds: 30), (timer) async {
          final position = await locationService.getCurrentLocation();
          if (position != null) {
            monitoringService.updateDriverLocation(
                auth.currentUser!.id, position);
          }
        });
      } else {
        debugPrint("Failed to start location tracking");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions required for monitoring'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  void _startDetection() {
    if (_controller == null || !_controller!.value.isInitialized || !_cameraInitialized) {
      debugPrint("Camera not ready for detection");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not ready. Please wait.')),
      );
      return;
    }

    if (_isDetecting || _isStreamingImages) {
      debugPrint("Detection already running");
      return;
    }

    _isDetecting = true;
    _isStreamingImages = true;

    try {
      _controller!.startImageStream((CameraImage image) {
        if (!_isDetecting || !mounted) return;

        if (_isDetecting) {
          _isDetecting = false;
          _processCameraImage(image).then((_) {
            if (mounted) _isDetecting = true;
          }).catchError((error) {
            debugPrint("Error processing image: $error");
            if (mounted) _isDetecting = true;
          });
        }
      });
      debugPrint("Image stream started successfully");
    } catch (e) {
      debugPrint("Error starting image stream: $e");
      _isDetecting = false;
      _isStreamingImages = false;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _stopDetection() {
    debugPrint("Stopping detection...");

    _isDetecting = false;
    _closedEyeFrames = 0;
    _alertTriggered = false;
    _eyeClosureTimer?.cancel();
    _stopAlert();

    if (_isStreamingImages &&
        _controller != null &&
        _controller!.value.isInitialized &&
        _controller!.value.isStreamingImages) {
      try {
        _controller!.stopImageStream();
        debugPrint("Image stream stopped successfully");
      } catch (e) {
        debugPrint("Error stopping image stream: $e");
      }
    }

    _isStreamingImages = false;

    if (mounted) {
      setState(() {});
    }
  }

  // [Rest of the methods remain the same - _processCameraImage, _getInputImageFromCameraImage, etc.]
  Future<void> _processCameraImage(CameraImage image) async {
    final inputImage = _getInputImageFromCameraImage(image, _controller!);
    if (inputImage == null) {
      return;
    }

    try {
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        if (face.leftEyeOpenProbability != null &&
            face.rightEyeOpenProbability != null) {
          final leftEyeOpen = face.leftEyeOpenProbability!;
          final rightEyeOpen = face.rightEyeOpenProbability!;

          bool isDrowsy = leftEyeOpen < 0.3 && rightEyeOpen < 0.3;

          if (isDrowsy) {
            _closedEyeFrames++;
            if (_closedEyeFrames > 15 && !_alertTriggered) {
              _triggerDrowsinessAlert();
            }
          } else {
            _closedEyeFrames = 0;
          }

          // Update monitoring service
          final auth = context.read<AuthService>();
          final monitoringService = context.read<MonitoringService>();
          if (auth.currentUser != null) {
            monitoringService.updateDrowsinessStatus(
              auth.currentUser!.id,
              isDrowsy,
              _closedEyeFrames,
            );
          }
        }
      } else {
        _closedEyeFrames = 0;
      }
    } catch (e) {
      debugPrint("Error processing image: $e");
    }
  }

  InputImage? _getInputImageFromCameraImage(
    CameraImage image,
    CameraController controller,
  ) {
    try {
      final camera = controller.description;
      final sensorOrientation = camera.sensorOrientation;

      InputImageRotation? rotation;

      if (Platform.isIOS) {
        switch (controller.value.deviceOrientation) {
          case DeviceOrientation.portraitUp:
            rotation = camera.lensDirection == CameraLensDirection.front
                ? InputImageRotation.rotation270deg
                : InputImageRotation.rotation90deg;
            break;
          case DeviceOrientation.portraitDown:
            rotation = camera.lensDirection == CameraLensDirection.front
                ? InputImageRotation.rotation90deg
                : InputImageRotation.rotation270deg;
            break;
          case DeviceOrientation.landscapeLeft:
            rotation = camera.lensDirection == CameraLensDirection.front
                ? InputImageRotation.rotation180deg
                : InputImageRotation.rotation0deg;
            break;
          case DeviceOrientation.landscapeRight:
            rotation = camera.lensDirection == CameraLensDirection.front
                ? InputImageRotation.rotation0deg
                : InputImageRotation.rotation180deg;
            break;
        }
      } else if (Platform.isAndroid) {
        var rotationCompensation =
            _orientations[controller.value.deviceOrientation];
        if (rotationCompensation == null) return null;

        if (camera.lensDirection == CameraLensDirection.front) {
          rotationCompensation =
              (sensorOrientation + rotationCompensation) % 360;
        } else {
          rotationCompensation =
              (sensorOrientation - rotationCompensation + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }

      if (rotation == null) return null;

      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      if (Platform.isIOS) {
        if (format != InputImageFormat.bgra8888) return null;
      } else {
        if (format != InputImageFormat.nv21 &&
            format != InputImageFormat.yuv420 &&
            format != InputImageFormat.yuv_420_888) return null;
      }

      final plane = image.planes.first;
      Uint8List bytes;
      InputImageFormat finalFormat = format;

      if (Platform.isAndroid &&
          (format == InputImageFormat.yuv420 ||
              format == InputImageFormat.yuv_420_888) &&
          image.planes.length >= 3) {
        bytes = _convertYUV420ToNV21(image);
        finalFormat = InputImageFormat.nv21;
      } else {
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        bytes = allBytes.done().buffer.asUint8List();
      }

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: finalFormat,
          bytesPerRow: plane.bytesPerRow,
        ),
      );

      return inputImage;
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      return null;
    }
  }

  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 4;
    final Uint8List nv21 = Uint8List(ySize + uvSize * 2);

    final Uint8List yPlane = image.planes[0].bytes;
    final int yRowStride = image.planes[0].bytesPerRow;
    final int yPixelStride = image.planes[0].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        nv21[y * width + x] = yPlane[y * yRowStride + x * yPixelStride];
      }
    }

    final Uint8List uPlane = image.planes[1].bytes;
    final Uint8List vPlane = image.planes[2].bytes;
    final int uRowStride = image.planes[1].bytesPerRow;
    final int vRowStride = image.planes[2].bytesPerRow;
    final int uPixelStride = image.planes[1].bytesPerPixel ?? 1;
    final int vPixelStride = image.planes[2].bytesPerPixel ?? 1;

    int uvIndex = ySize;
    for (int y = 0; y < height ~/ 2; y++) {
      for (int x = 0; x < width ~/ 2; x++) {
        final int uIdx = y * uRowStride + x * uPixelStride;
        final int vIdx = y * vRowStride + x * vPixelStride;

        if (uIdx < uPlane.length &&
            vIdx < vPlane.length &&
            uvIndex + 1 < nv21.length) {
          nv21[uvIndex] = vPlane[vIdx];
          nv21[uvIndex + 1] = uPlane[uIdx];
          uvIndex += 2;
        }
      }
    }

    return nv21;
  }

  void _triggerDrowsinessAlert() async {
    if (_alertTriggered) return;
    _alertTriggered = true;
    debugPrint("⚠️ Gentle Alert: Possible Drowsiness Detected!");

    try {
      await _audioPlayer.play(AssetSource('sounds/beep.wav'), volume: 0.5);
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: [0, 300, 150, 300]);
      }
    } catch (e) {
      debugPrint("Error playing gentle alert: $e");
    }

    if (mounted) {
      _showGentleOverlay();
    }

    _alertEscalationTimer = Timer(const Duration(seconds: 5), () async {
      if (_alertTriggered && mounted) {
        debugPrint("⚠️ Escalating Alert: Still no acknowledgment.");
        try {
          await _audioPlayer.play(AssetSource('sounds/alarm.wav'), volume: 1.0);
          if (await Vibration.hasVibrator()) {
            Vibration.vibrate(pattern: [0, 600, 200, 600, 200, 600]);
          }
        } catch (e) {
          debugPrint("Error playing escalated alert: $e");
        }
        _showEscalatedOverlay();
      }
    });

    _autoStopTimer = Timer(const Duration(seconds: 15), () {
      if (_alertTriggered && mounted) {
        _stopAlert();
      }
    });
  }

  void _stopAlert() {
    _audioPlayer.stop();
    Vibration.cancel();
    _alertTriggered = false;
    _alertEscalationTimer?.cancel();
    _autoStopTimer?.cancel();
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showGentleOverlay() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.3),
        builder: (ctx) {
          return AlertDialog(
            title: const Text("Stay Alert"),
            content: const Text(
                "It seems you may be feeling drowsy. Please take a break."),
            actions: [
              TextButton(
                onPressed: _stopAlert,
                child: const Text("I'm Okay"),
              ),
            ],
          );
        },
      );
    }
  }

  void _showEscalatedOverlay() {
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.6),
        builder: (ctx) {
          return AlertDialog(
            title: const Text(
              "⚠️ Warning",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: const Text(
                "Please pull over safely and rest before continuing."),
            actions: [
              TextButton(
                onPressed: _stopAlert,
                child: const Text("I Understand"),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _stopDetection();
    _locationUpdateTimer?.cancel();
    _eyeClosureTimer?.cancel();
    _alertEscalationTimer?.cancel();
    _autoStopTimer?.cancel();

    _audioPlayer.dispose();
    _faceDetector.close();

    if (_controller != null) {
      _controller!.dispose();
    }

    // Stop monitoring services
    final auth = context.read<AuthService>();
    final monitoringService = context.read<MonitoringService>();
    final locationService = context.read<LocationService>();

    if (auth.currentUser != null) {
      monitoringService.stopMonitoring(auth.currentUser!.id);
    }
    locationService.stopLocationTracking();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    if (!_cameraInitialized || _controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Driver Mode'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing camera...'),
              SizedBox(height: 8),
              Text('Please wait while we set up your safety monitoring.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Mode'),
        backgroundColor: Colors.blue,
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
                      leading: const Icon(Icons.info),
                      title: Text(
                          'Driver: ${auth.currentUser?.email ?? 'Unknown'}'),
                      subtitle: Text(
                          'Bus: ${auth.currentUser?.busNumber ?? 'Unknown'}'),
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
      body: Column(
        children: [
          // Status indicator
          Consumer3<MonitoringService, LocationService, AuthService>(
            builder: (context, monitoring, location, auth, _) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: monitoring.isMonitoring && location.isTracking
                    ? Colors.green[100]
                    : Colors.orange[100],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      monitoring.isMonitoring && location.isTracking
                          ? Icons.security
                          : Icons.warning,
                      color: monitoring.isMonitoring && location.isTracking
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      monitoring.isMonitoring && location.isTracking
                          ? 'Monitoring Active - HQ Connected'
                          : 'Monitoring Inactive',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: monitoring.isMonitoring && location.isTracking
                            ? Colors.green[700]
                            : Colors.orange[700],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Camera preview
          Expanded(
            child: Stack(
              children: [
                CameraPreview(_controller!),

                // Drowsiness indicator overlay
                if (_closedEyeFrames > 10)
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _closedEyeFrames > 20
                            ? Colors.red.withOpacity(0.9)
                            : Colors.orange.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.remove_red_eye,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Eyes Closed: $_closedEyeFrames',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Location and monitoring info
          Consumer2<LocationService, MonitoringService>(
            builder: (context, location, monitoring, _) {
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoCard(
                          'Location',
                          location.currentPosition != null && location.isTracking
                              ? 'Active'
                              : 'Inactive',
                          location.currentPosition != null && location.isTracking
                              ? Icons.location_on
                              : Icons.location_off,
                          location.currentPosition != null && location.isTracking
                              ? Colors.green
                              : Colors.red,
                        ),
                        _buildInfoCard(
                          'Monitoring',
                          monitoring.isMonitoring ? 'Active' : 'Inactive',
                          monitoring.isMonitoring
                              ? Icons.visibility
                              : Icons.visibility_off,
                          monitoring.isMonitoring ? Colors.green : Colors.red,
                        ),
                        _buildInfoCard(
                          'HQ Connection',
                          monitoring.currentDriverStatus?.isOnline == true
                              ? 'Online'
                              : 'Offline',
                          monitoring.currentDriverStatus?.isOnline == true
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                          monitoring.currentDriverStatus?.isOnline == true
                              ? Colors.green
                              : Colors.red,
                        ),
                      ],
                    ),
                    if (location.currentPosition != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Speed: ${(location.currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    if (location.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Location Error: ${location.errorMessage}',
                          style: const TextStyle(fontSize: 10, color: Colors.red),
                        ),
                      ),
                  ],
                ),
              );
            },
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
                      backgroundColor:
                          _isStreamingImages ? Colors.green : Colors.blue,
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
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Text(
          value,
          style: TextStyle(fontSize: 10, color: color),
        ),
      ],
    );
  }
}