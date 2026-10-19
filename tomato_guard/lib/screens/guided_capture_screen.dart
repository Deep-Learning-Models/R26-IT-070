import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/quality_analyzer.dart';
import '../services/leaf_detector.dart';
import '../theme/app_theme.dart';

class GuidedCaptureScreen extends StatefulWidget {
  const GuidedCaptureScreen({Key? key}) : super(key: key);

  @override
  State<GuidedCaptureScreen> createState() => _GuidedCaptureScreenState();
}

class _GuidedCaptureScreenState extends State<GuidedCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  final LeafDetector _leafDetector = LeafDetector();
  BoundingBox? _currentBox;

  bool _isCameraInitialized = false;
  bool _isPermissionGranted = false;
  bool _isAnalyzing = false;
  bool _isTakingPicture = false;

  QualityAnalysisResult _currentQuality = const QualityAnalysisResult(
      CaptureQuality.poor, "Loading TFLite model...");

  DateTime _lastAnalysisTime = DateTime.now();
  final int _analysisIntervalMs = 150;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSystem();
  }

  Future<void> _initSystem() async {
    // 1. Load the YOLOv8n model
    await _leafDetector.loadModel();
    if (mounted) {
      setState(() {
        _currentQuality = const QualityAnalysisResult(
            CaptureQuality.poor, "Initializing camera...");
      });
    }
    // 2. Setup Camera
    await _checkPermissionsAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _cameraController = null;
    _leafDetector.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    if (state == AppLifecycleState.inactive) {
      _cameraController = null;
      _isCameraInitialized = false;
      cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (cameraController == null && mounted && _isPermissionGranted) {
        _setupCameras();
      }
    }
  }

  Future<void> _checkPermissionsAndInit() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      setState(() => _isPermissionGranted = true);
      _setupCameras();
    } else {
      setState(() => _isPermissionGranted = false);
    }
  }

  Future<void> _setupCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        final backCamera = _cameras!.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras!.first,
        );
        await _initCamera(backCamera);
      }
    } catch (e) {
      debugPrint('Error setting up cameras: $e');
    }
  }

  Future<void> _initCamera(CameraDescription description) async {
    final controller = CameraController(
      description,
      ResolutionPreset.medium, // Optimal 60fps mobile preview
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _cameraController = controller;

    try {
      await controller.initialize();
      if (!mounted || _cameraController != controller) {
        await controller.dispose();
        return;
      }
      setState(() => _isCameraInitialized = true);

      await controller.startImageStream((CameraImage image) async {
        if (!mounted || _cameraController != controller) return;
        if (_isAnalyzing || _isTakingPicture) return;

        final now = DateTime.now();
        if (now.difference(_lastAnalysisTime).inMilliseconds <
            _analysisIntervalMs) {
          return;
        }

        _isAnalyzing = true;
        _lastAnalysisTime = now;

        try {
          // 1. Detect Leaf via fast YOLO
          final BoundingBox? box = await _leafDetector.detect(image);

          // 2. Analyze quality rules (Area, Centering, Lighting, Blur)
          final result = await QualityAnalyzer.analyze(image, box);

          if (mounted) {
            setState(() {
              // Smooth box transition if box exists
              if (box != null && _currentBox != null) {
                _currentBox = BoundingBox(
                  x: _currentBox!.x * 0.3 + box.x * 0.7,
                  y: _currentBox!.y * 0.3 + box.y * 0.7,
                  width: _currentBox!.width * 0.3 + box.width * 0.7,
                  height: _currentBox!.height * 0.3 + box.height * 0.7,
                  confidence: box.confidence,
                );
              } else {
                _currentBox = box;
              }
              _currentQuality = result;
            });
          }
        } catch (e) {
          debugPrint('Error analyzing frame: $e');
        } finally {
          _isAnalyzing = false;
        }
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isTakingPicture) {
      return;
    }

    setState(() => _isTakingPicture = true);

    try {
      await _cameraController!.stopImageStream();
      final XFile imageFile = await _cameraController!.takePicture();

      if (mounted) {
        Navigator.pop(context, imageFile);
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture image: $e'),
            backgroundColor: AppTheme.severitySevere,
          ),
        );
        setState(() {
          _isTakingPicture = false;
        });
        _cameraController?.startImageStream((image) {});
      }
    }
  }

  Color _getQualityColor() {
    switch (_currentQuality.quality) {
      case CaptureQuality.good:
        return AppTheme.severityMild; // Green
      case CaptureQuality.fair:
        return AppTheme.severityModerate; // Yellow
      case CaptureQuality.poor:
        return AppTheme.severitySevere; // Red
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPermissionGranted) {
      return _buildPermissionDeniedState();
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryDark),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final double scaleX = size.width;
    final double scaleY = size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full Screen Camera Preview
          CameraPreview(_cameraController!),

          // 2. Center Target Guide / Viewfinder Reticle
          CustomPaint(
            painter: CenterReticlePainter(
              color: _getQualityColor().withOpacity(0.85),
              isGood: _currentQuality.quality == CaptureQuality.good,
            ),
          ),

          // 3. Dynamic Bounding Box Overlay
          if (_currentBox != null)
            CustomPaint(
              painter: BoundingBoxPainter(
                box: _currentBox!,
                color: _getQualityColor(),
                scaleX: scaleX,
                scaleY: scaleY,
              ),
            ),

          // 3. Status Banner
          Positioned(
            top: 52,
            left: 64,
            right: 20,
            child: _buildStatusBanner(),
          ),

          // 5. Capture Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: _buildCaptureControls(),
          ),

          // 6. Back Button
          Positioned(
            top: 48,
            left: 12,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final boxColor = _getQualityColor();
    final String confStr = _currentBox != null
        ? " (${(_currentBox!.confidence * 100.0).clamp(0.0, 100.0).toStringAsFixed(1)}%)"
        : "";
    final displayMessage = "${_currentQuality.message}$confStr";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35), // Transparent glass backdrop
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: boxColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: boxColor.withOpacity(0.25),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _currentQuality.quality == CaptureQuality.good
                ? Icons.check_circle_rounded
                : Icons.center_focus_strong_rounded,
            color: boxColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black87,
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureControls() {
    final isGood = _currentQuality.quality == CaptureQuality.good;

    // Hide capture button if not good
    if (!isGood && !_isTakingPicture) {
      return const SizedBox(height: 100);
    }

    return Column(
      children: [
        if (_isTakingPicture)
          const CircularProgressIndicator(color: AppTheme.primaryDark)
        else
          GestureDetector(
            onTap: _captureImage,
            child: Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryDark,
                  width: 4,
                ),
              ),
              child: Center(
                child: Container(
                  height: 65,
                  width: 65,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt,
                      color: Colors.white, size: 30),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPermissionDeniedState() {
    return Scaffold(
      backgroundColor: AppTheme.softBackground,
      appBar: AppBar(title: const Text('Camera Permission')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  size: 64, color: AppTheme.primaryDark),
              const SizedBox(height: 16),
              const Text(
                'Camera Access Required',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => openAppSettings(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryDark,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom Painter to draw YOLO bounding box over the camera preview
class BoundingBoxPainter extends CustomPainter {
  final BoundingBox box;
  final Color color;
  final double scaleX;
  final double scaleY;

  BoundingBoxPainter({
    required this.box,
    required this.color,
    required this.scaleX,
    required this.scaleY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final rect = Rect.fromLTWH(box.x * size.width, box.y * size.height,
        box.width * size.width, box.height * size.height);

    // Draw filled transparent background
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)), fillPaint);
    // Draw thick border
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)), paint);

    // Draw live confidence score badge
    final double scorePercent = (box.confidence * 100.0).clamp(0.0, 100.0);
    final String labelText = "Tomato Leaf ${scorePercent.toStringAsFixed(1)}%";
    final TextSpan span = TextSpan(
      text: labelText,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();

    const double padH = 8.0;
    const double padV = 4.0;
    final double bgW = tp.width + (padH * 2);
    final double bgH = tp.height + (padV * 2);
    final double badgeLeft =
        rect.left.clamp(0.0, (size.width - bgW).clamp(0.0, size.width));
    final double badgeTop = (rect.top - bgH - 6)
        .clamp(0.0, (size.height - bgH).clamp(0.0, size.height));

    final RRect badgeRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeLeft, badgeTop, bgW, bgH),
      const Radius.circular(6),
    );
    final Paint badgeBgPaint = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(badgeRRect, badgeBgPaint);
    tp.paint(canvas, Offset(badgeLeft + padH, badgeTop + padV));
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.box != box || oldDelegate.color != color;
  }
}

// Custom Painter to draw a clean center target reticle (corner guides)
class CenterReticlePainter extends CustomPainter {
  final Color color;
  final bool isGood;

  CenterReticlePainter({required this.color, required this.isGood});

  @override
  void paint(Canvas canvas, Size size) {
    final double targetWidth = size.width * 0.68;
    final double targetHeight = size.height * 0.48;
    final double left = (size.width - targetWidth) / 2;
    final double top = (size.height - targetHeight) / 2;
    final double right = left + targetWidth;
    final double bottom = top + targetHeight;

    final double cornerLength = 26.0;
    final double radius = 14.0;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isGood ? 3.5 : 2.0
      ..strokeCap = StrokeCap.round;

    // Top-Left Corner
    final pathTL = Path()
      ..moveTo(left, top + cornerLength)
      ..lineTo(left, top + radius)
      ..arcToPoint(Offset(left + radius, top), radius: Radius.circular(radius))
      ..lineTo(left + cornerLength, top);
    canvas.drawPath(pathTL, paint);

    // Top-Right Corner
    final pathTR = Path()
      ..moveTo(right - cornerLength, top)
      ..lineTo(right - radius, top)
      ..arcToPoint(Offset(right, top + radius), radius: Radius.circular(radius))
      ..lineTo(right, top + cornerLength);
    canvas.drawPath(pathTR, paint);

    // Bottom-Left Corner
    final pathBL = Path()
      ..moveTo(left, bottom - cornerLength)
      ..lineTo(left, bottom - radius)
      ..arcToPoint(Offset(left + radius, bottom),
          radius: Radius.circular(radius))
      ..lineTo(left + cornerLength, bottom);
    canvas.drawPath(pathBL, paint);

    // Bottom-Right Corner
    final pathBR = Path()
      ..moveTo(right - cornerLength, bottom)
      ..lineTo(right - radius, bottom)
      ..arcToPoint(Offset(right, bottom - radius),
          radius: Radius.circular(radius))
      ..lineTo(right, bottom - cornerLength);
    canvas.drawPath(pathBR, paint);

    // Center Crosshair / Dot indicator
    final centerPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2),
        isGood ? 4.0 : 2.5, centerPaint);
  }

  @override
  bool shouldRepaint(covariant CenterReticlePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isGood != isGood;
  }
}
