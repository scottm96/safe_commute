import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';
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
  int _closedEyeFrames = 0;
  bool _alertTriggered = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _alertEscalationTimer;
  Timer? _autoStopTimer;

  // Android orientation mapping
  final Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

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
    _stopAlert();
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final inputImage = _getInputImageFromCameraImage(image, _controller!);
      if (inputImage == null) return;

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

  InputImage? _getInputImageFromCameraImage(
    CameraImage image,
    CameraController controller,
  ) {
    try {
      final camera = controller.description;
      final sensorOrientation = camera.sensorOrientation;
      final isIOS = Platform.isIOS;

      // --- Determine rotation ---
      InputImageRotation? rotation;
      if (isIOS) {
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
      } else {
        var rotationComp = _orientations[controller.value.deviceOrientation];
        if (rotationComp == null) return null;

        rotationComp = camera.lensDirection == CameraLensDirection.front
            ? (sensorOrientation + rotationComp) % 360
            : (sensorOrientation - rotationComp + 360) % 360;

        rotation = InputImageRotationValue.fromRawValue(rotationComp);
      }
      if (rotation == null) return null;

      // --- Validate format ---
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      if (isIOS && format != InputImageFormat.bgra8888) return null;
      if (!isIOS &&
          format != InputImageFormat.nv21 &&
          format != InputImageFormat.yuv420 &&
          format != InputImageFormat.yuv_420_888) {
        return null;
      }

      // --- Plane validation ---
      if (isIOS && image.planes.length != 1) return null;
      if (!isIOS) {
        if (format == InputImageFormat.nv21 && image.planes.length != 1) {
          return null;
        }
        if ((format == InputImageFormat.yuv420 ||
                format == InputImageFormat.yuv_420_888) &&
            image.planes.isEmpty) {
          return null;
        }
      }

      // --- Convert if needed ---
      Uint8List bytes;
      InputImageFormat finalFormat = format;
      if (!isIOS &&
          (format == InputImageFormat.yuv420 ||
              format == InputImageFormat.yuv_420_888) &&
          image.planes.length >= 3) {
        bytes = _convertYUV420ToNV21(image);
        finalFormat = InputImageFormat.nv21;
      } else {
        bytes = image.planes.first.bytes;
      }

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: finalFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
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

    // Copy Y plane
    final Uint8List yPlane = image.planes[0].bytes;
    final int yRowStride = image.planes[0].bytesPerRow;
    final int yPixelStride = image.planes[0].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        nv21[y * width + x] = yPlane[y * yRowStride + x * yPixelStride];
      }
    }

    // Copy UV planes
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
    debugPrint("⚠ Gentle Alert: Possible Drowsiness Detected!");

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
        debugPrint("⚠ Escalating Alert: Still no acknowledgment.");
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
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showGentleOverlay() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.3),
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
      Navigator.of(context, rootNavigator: true).pop();
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.3),
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
