/*import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class DriverScreen extends StatefulWidget {
  const DriverScreen ({super.key});

  @override
  _DriverScreenState createState() {
    return _DriverScreenState();
  }
}

class _DriverScreenState extends State<DriverScreen> {
  final faceDetector = GoogleMlKit.vision.faceDetector();
  CameraController? _controller;
  List<CameraDescription>? cameras;

  @override
  void initState(){
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    _controller = CameraController(cameras![0], ResolutionPreset.medium);
    await _controller!.initialize();
    setState(() {});
  }

  Future<void> _processImage(CameraImage image) async {
    final inputImage = InputImage.fromBytes(...); // Convert CameraImage to InputImage
    final faces = await faceDetector.processImage(inputImage);
    for (Face face in faces) {
      if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
        double ear = (face.leftEyeOpenProbability! + face.rightEyeOpenProbability!) / 2;
        if (ear < 0.3) {
          // Drowsiness detected (adjust threshold as needed)
        }
      }
    }
  }

  @override
  Widget build(BuildContext context){
    if (_controller == null || !_controller!.value.isInitialized) {
      return Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: Text('Driver Mode')),
      body: Column(
        children: [
          // CameraPreview will go here
          Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {}, // Placeholder for starting detection
                child: Text('Start Detection'),
              ),
              SizedBox(width: 20),
              ElevatedButton(
                onPressed: () {}, // Placeholder for stopping detection
                child: Text('Stop Detection'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}*/

import 'dart:async';
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  _DriverScreenState createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  late FaceDetector _faceDetector;

  bool _isDetecting = false;
  Timer? _eyeClosureTimer;
  int _closedEyeFrames = 0;
  bool _alertTriggered = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeFaceDetector();
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true, // Eye open probability
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate, // More accurate but slower
    );
    _faceDetector = GoogleMlKit.vision.faceDetector(options);
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    // Prefer front camera
    final frontCamera = cameras!.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => cameras!.first,
    );

    _controller = CameraController(frontCamera, ResolutionPreset.medium);
    await _controller!.initialize();
    setState(() {});
  }

  void _startDetection() {
    if (_controller == null) return;

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
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      // Convert image for ML Kit
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final camera = _controller!.description;
      final imageRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;
      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;
      final planeData = image.planes.map(
        (Plane plane) {
          return InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          );
        },
      ).toList();

      final inputImageData = InputImageData(
        size: imageSize,
        imageRotation: imageRotation,
        inputImageFormat: inputImageFormat,
        planeData: planeData,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        inputImageData: inputImageData,
      );

      // Process image with face detector
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;

        if (face.leftEyeOpenProbability != null &&
            face.rightEyeOpenProbability != null) {
          final leftEyeOpen = face.leftEyeOpenProbability!;
          final rightEyeOpen = face.rightEyeOpenProbability!;

          // Eye closure detection threshold
          if (leftEyeOpen < 0.3 && rightEyeOpen < 0.3) {
            _closedEyeFrames++;
            if (_closedEyeFrames > 15 && !_alertTriggered) {
              _triggerDrowsinessAlert();
            }
          } else {
            _closedEyeFrames = 0;
          }
        }
      }
    } catch (e) {
      debugPrint("Error in processing image: $e");
    }
  }

  void _triggerDrowsinessAlert() {
    _alertTriggered = true;
    debugPrint("⚠ ALERT: Possible Drowsiness Detected!");
    // TODO: Add sound, vibration, or UI alert here
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    _eyeClosureTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
