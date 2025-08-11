import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  Timer? _eyeClosureTimer;
  int _closedEyeFrames = 0;
  bool _alertTriggered = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _alertEscalationTimer;
  Timer? _autoStopTimer;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _initializeCamera();
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _initializeCamera() async {
    try {
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
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  void _startDetection() {
    if (_controller == null || !_controller!.value.isInitialized) {
      debugPrint("Camera not initialized");
      return;
    }

    _isDetecting = false; // Reset to allow detection
    _controller!.startImageStream((CameraImage image) {
      if (_isDetecting) return;
      _isDetecting = true;
      _processCameraImage(image).then((_) {
        _isDetecting = false;
      });
    });
  }

  void _stopDetection() {
    _controller?.stopImageStream();
    _closedEyeFrames = 0;
    _alertTriggered = false;
    _eyeClosureTimer?.cancel();
    _stopAlert();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());
      final camera = _controller!.description;
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;
      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final inputImageMetadata = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageMetadata,
      );

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        if (face.leftEyeOpenProbability != null &&
            face.rightEyeOpenProbability != null) {
          final leftEyeOpen = face.leftEyeOpenProbability!;
          final rightEyeOpen = face.rightEyeOpenProbability!;
          if (leftEyeOpen < 0.3 && rightEyeOpen < 0.3) {
            _closedEyeFrames++;
            if (_closedEyeFrames > 15 && !_alertTriggered) {
              _triggerDrowsinessAlert();
            }
          } else {
            _closedEyeFrames = 0;
          }
        }
      } else {
        _closedEyeFrames = 0; // Reset if no face detected
      }
    } catch (e) {
      debugPrint("Error processing image: $e");
    }
  }

  void _triggerDrowsinessAlert() async {
    if (_alertTriggered) return;
    _alertTriggered = true;
    debugPrint("⚠ Gentle Alert: Possible Drowsiness Detected!");

    try {
      await _audioPlayer.play(AssetSource('sounds/beep.wav'), volume: 0.5);
      if (await Vibration.hasVibrator() ?? false) {
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
        debugPrint("⚠ Escalating Alert: Still no acknowledgment.");
        try {
          await _audioPlayer.play(AssetSource('sounds/alarm.wav'), volume: 1.0);
          if (await Vibration.hasVibrator() ?? false) {
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
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Close overlay
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
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Close gentle overlay
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withOpacity(0.6),
        builder: (ctx) {
          return AlertDialog(
            title: const Text(
              "⚠ Warning",
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

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _faceDetector.close();
    _eyeClosureTimer?.cancel();
    _alertEscalationTimer?.cancel();
    _autoStopTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Mode')),
      body: Column(
        children: [
          Expanded(
            child: CameraPreview(_controller!),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _startDetection,
                  child: const Text('Start Detection'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _stopDetection,
                  child: const Text('Stop Detection'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
