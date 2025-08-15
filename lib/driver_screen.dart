import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  late FaceDetector _faceDetector;
  bool _isDetecting = false;
  bool _isStreamingImages = false; // Track if image stream is active
  Timer? _eyeClosureTimer;
  int _closedEyeFrames = 0;
  bool _alertTriggered = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _alertEscalationTimer;
  Timer? _autoStopTimer;

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeFaceDetector();
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // App is going to background or being closed
      _stopDetection();
    } else if (state == AppLifecycleState.resumed) {
      // App is coming back to foreground
      // Optionally restart detection if it was running before
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
        ResolutionPreset.low,
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

    if (_isDetecting || _isStreamingImages) {
      debugPrint("Detection already running or image stream active");
      return;
    }

    _isDetecting = true;
    _isStreamingImages = true;

    try {
      _controller!.startImageStream((CameraImage image) {
        if (!_isDetecting) return;
        
        // Use a flag to prevent multiple simultaneous processing
        if (_isDetecting) {
          _isDetecting = false;
          _processCameraImage(image).then((_) {
            _isDetecting = true;
          }).catchError((error) {
            debugPrint("Error processing image: $error");
            _isDetecting = true;
          });
        }
      });
    } catch (e) {
      debugPrint("Error starting image stream: $e");
      _isDetecting = false;
      _isStreamingImages = false;
    }

    // Update the UI
    if (mounted) {
      setState(() {});
    }
  }

  void _stopDetection() {
    debugPrint("Stopping detection...");
    
    // Stop processing first
    _isDetecting = false;
    
    // Reset detection state
    _closedEyeFrames = 0;
    _alertTriggered = false;
    _eyeClosureTimer?.cancel();
    _stopAlert();

    // Stop image stream only if it's active and controller is available
    if (_isStreamingImages && 
        _controller != null && 
        _controller!.value.isInitialized &&
        _controller!.value.isStreamingImages) {
      try {
        _controller!.stopImageStream();
        debugPrint("Image stream stopped successfully");
      } catch (e) {
        debugPrint("Error stopping image stream: $e");
        // Don't rethrow the error, just log it
      }
    }
    
    _isStreamingImages = false;

    // Update the UI
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    final inputImage = _getInputImageFromCameraImage(image, _controller!);
    if (inputImage == null) {
      debugPrint("❌ Failed to get a valid InputImage.");
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
    debugPrint('🔄 [CONVERT] Starting image conversion...');
    try {
      final camera = controller.description;
      final sensorOrientation = camera.sensorOrientation;
      debugPrint('🔄 [CONVERT] Camera sensor orientation: $sensorOrientation');
      debugPrint('🔄 [CONVERT] Platform: ${Platform.isIOS ? "iOS" : "Android"}');

      InputImageRotation? rotation;

      if (Platform.isIOS) {
        debugPrint('📱 [CONVERT] iOS device detected');
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
        debugPrint('📱 [CONVERT] iOS rotation set to: $rotation');
      } else if (Platform.isAndroid) {
        debugPrint('🤖 [CONVERT] Android device detected');
        var rotationCompensation =
            _orientations[controller.value.deviceOrientation];
        debugPrint('🔄 [CONVERT] Device orientation: ${controller.value.deviceOrientation}');
        debugPrint('🔄 [CONVERT] Rotation compensation: $rotationCompensation');

        if (rotationCompensation == null) {
          debugPrint('❌ [CONVERT] No rotation compensation found');
          return null;
        }

        if (camera.lensDirection == CameraLensDirection.front) {
          debugPrint('📷 [CONVERT] Front-facing camera');
          rotationCompensation =
              (sensorOrientation + rotationCompensation) % 360;
        } else {
          debugPrint('📷 [CONVERT] Back-facing camera');
          rotationCompensation =
              (sensorOrientation - rotationCompensation + 360) % 360;
        }
        debugPrint('🔄 [CONVERT] Final rotation compensation: $rotationCompensation');
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }

      if (rotation == null) {
        debugPrint('❌ [CONVERT] Failed to determine rotation');
        return null;
      }
      debugPrint('✅ [CONVERT] Rotation determined: $rotation');

      debugPrint('🔄 [CONVERT] Image format raw value: ${image.format.raw}');
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      debugPrint('🔄 [CONVERT] Converted format: $format');

      if (format == null) {
        debugPrint('❌ [CONVERT] Unsupported image format: ${image.format.raw}');
        return null;
      }

      if (Platform.isIOS) {
        if (format != InputImageFormat.bgra8888) {
          debugPrint('❌ [CONVERT] iOS: Expected bgra8888 format, got $format');
          return null;
        }
        debugPrint('✅ [CONVERT] iOS: BGRA8888 format validated');
      } else {
        if (format != InputImageFormat.nv21 &&
            format != InputImageFormat.yuv420 &&
            format != InputImageFormat.yuv_420_888) {
          debugPrint(
            '❌ [CONVERT] Android: Expected nv21, yuv420, or yuv_420_888 format, got $format',
          );
          return null;
        }
        debugPrint('✅ [CONVERT] Android: Format validation passed');
      }

      if (Platform.isIOS) {
        if (image.planes.length != 1) {
          debugPrint('❌ [CONVERT] iOS expected 1 plane, got ${image.planes.length}');
          return null;
        }
        debugPrint('✅ [CONVERT] iOS: Single plane validated');
      } else {
        if (format == InputImageFormat.nv21) {
          if (image.planes.length != 1) {
            debugPrint('❌ [CONVERT] NV21 expected 1 plane, got ${image.planes.length}');
            return null;
          }
        } else if (format == InputImageFormat.yuv420 ||
            format == InputImageFormat.yuv_420_888) {
          if (image.planes.isEmpty) {
            debugPrint('❌ [CONVERT] YUV420/YUV_420_888 has no planes');
            return null;
          }
          debugPrint('🔄 [CONVERT] YUV420/YUV_420_888 has ${image.planes.length} planes, using first plane');
        }
      }

      final plane = image.planes.first;
      debugPrint('🔄 [CONVERT] Plane bytes length: ${plane.bytes.length}');
      debugPrint('🔄 [CONVERT] Plane bytes per row: ${plane.bytesPerRow}');

      Uint8List bytes;
      InputImageFormat finalFormat = format;

      if (Platform.isAndroid &&
          (format == InputImageFormat.yuv420 ||
              format == InputImageFormat.yuv_420_888) &&
          image.planes.length >= 3) {
        debugPrint('🔄 [CONVERT] Converting YUV_420_888 to NV21...');
        bytes = _convertYUV420ToNV21(image);
        finalFormat = InputImageFormat.nv21;
        debugPrint('🔄 [CONVERT] Converted bytes length: ${bytes.length}');
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

      debugPrint('✅ [CONVERT] InputImage created successfully');
      return inputImage;
    } catch (e) {
      debugPrint('❌ [CONVERT] Error converting camera image: $e');
      debugPrint('❌ [CONVERT] Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  Uint8List _convertYUV420ToNV21(CameraImage image) {
    debugPrint('🔄 [YUV] Converting YUV420 to NV21...');
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 4;

    final Uint8List nv21 = Uint8List(ySize + uvSize * 2);

    final Uint8List yPlane = image.planes[0].bytes;
    final int yRowStride = image.planes[0].bytesPerRow;
    final int yPixelStride = image.planes[0].bytesPerPixel ?? 1;

    debugPrint('🔄 [YUV] Y plane - size: ${yPlane.length}, rowStride: $yRowStride, pixelStride: $yPixelStride');

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

    debugPrint('🔄 [YUV] U plane - size: ${uPlane.length}, rowStride: $uRowStride, pixelStride: $uPixelStride');
    debugPrint('🔄 [YUV] V plane - size: ${vPlane.length}, rowStride: $vRowStride, pixelStride: $vPixelStride');

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

    debugPrint('✅ [YUV] YUV420 to NV21 conversion complete');
    return nv21;
  }

  void _triggerDrowsinessAlert() async {
    if (_alertTriggered) return;
    _alertTriggered = true;
    debugPrint("⚠️ Gentle Alert: Possible Drowsiness Detected!");

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
        debugPrint("⚠️ Escalating Alert: Still no acknowledgment.");
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    // Stop detection first
    _stopDetection();
    
    // Clean up timers
    _eyeClosureTimer?.cancel();
    _alertEscalationTimer?.cancel();
    _autoStopTimer?.cancel();
    
    // Clean up audio
    _audioPlayer.dispose();
    
    // Clean up face detector
    _faceDetector.close();
    
    // Clean up camera controller
    if (_controller != null) {
      _controller!.dispose();
    }
    
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
                  onPressed: (!_isDetecting && !_isStreamingImages) ? _startDetection : null,
                  child: Text(_isStreamingImages ? 'Detection Running...' : 'Start Detection'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _isStreamingImages ? _stopDetection : null,
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