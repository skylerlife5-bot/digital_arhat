import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum _LivenessStage {
  waitingForFace,
  waitingForBlink,
  waitingForTurnLeft,
  waitingForTurnRight,
  verifying,
  success,
  failed,
}

class LivenessDetectionScreen extends StatefulWidget {
  const LivenessDetectionScreen({super.key});

  @override
  State<LivenessDetectionScreen> createState() =>
      _LivenessDetectionScreenState();
}

class _LivenessDetectionScreenState extends State<LivenessDetectionScreen> {
  static const Color _deepGreen = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  static const Duration _challengeTimeout = Duration(seconds: 10);
  static const int _maxAttempts = 3;

  CameraController? _controller;
  FaceDetector? _faceDetector;
  bool _isBusy = false;
  bool _eyesPreviouslyOpen = false;
  bool _showRetry = false;
  _LivenessStage _stage = _LivenessStage.waitingForFace;
  int _attemptsUsed = 0;

  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
      ),
    );
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final CameraDescription frontCamera = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final CameraController controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      _controller = controller;
      await _startImageStream();
      _startChallengeTimeout();

      if (mounted) {
        setState(() {
          _stage = _LivenessStage.waitingForFace;
          _attemptsUsed = 0;
        });
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _startImageStream() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;

    await controller.startImageStream((CameraImage image) {
      if (_isBusy ||
          _stage == _LivenessStage.verifying ||
          _stage == _LivenessStage.success) {
        return;
      }
      _processImage(image);
    });
  }

  Future<void> _stopImageStreamIfNeeded() async {
    final CameraController? controller = _controller;
    if (controller == null) return;
    if (!controller.value.isStreamingImages) return;
    await controller.stopImageStream();
  }

  void _startChallengeTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_challengeTimeout, () {
      if (!mounted) return;
      if (_stage == _LivenessStage.waitingForFace ||
          _stage == _LivenessStage.waitingForBlink ||
          _stage == _LivenessStage.waitingForTurnLeft ||
          _stage == _LivenessStage.waitingForTurnRight) {
        _failCurrentAttempt(
          'Challenge time khatam ho gaya / وقت ختم ہوگیا، دوبارہ کوشش کریں',
        );
      }
    });
  }

  Future<void> _failCurrentAttempt(String message) async {
    _timeoutTimer?.cancel();
    final int nextAttempts = _attemptsUsed + 1;
    if (!mounted) return;

    if (nextAttempts >= _maxAttempts) {
      await _stopImageStreamIfNeeded();
      if (!mounted) return;
      setState(() {
        _attemptsUsed = nextAttempts;
        _showRetry = false;
        _stage = _LivenessStage.failed;
      });
      _showSnack(
        'Liveness failed after 3 attempts / لائیونیس 3 کوششوں کے بعد ناکام ہوگئی',
      );
      return;
    }

    setState(() {
      _attemptsUsed = nextAttempts;
      _eyesPreviouslyOpen = false;
      _showRetry = true;
      _stage = _LivenessStage.waitingForFace;
    });
    _showSnack(
      '$message (${_maxAttempts - nextAttempts} tries left / کوششیں باقی)',
    );
  }

  InputImage _buildInputImage(CameraImage image, CameraController controller) {
    if (Platform.isIOS) {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      return InputImage.fromBytes(
        bytes: allBytes.done().buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation:
              InputImageRotationValue.fromRawValue(
                controller.description.sensorOrientation,
              ) ??
              InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    final Uint8List nv21Bytes = _convertYuv420ToNv21(image);
    return InputImage.fromBytes(
      bytes: nv21Bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation:
            InputImageRotationValue.fromRawValue(
              controller.description.sensorOrientation,
            ) ??
            InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

  Uint8List _convertYuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 2;
    final Uint8List nv21 = Uint8List(ySize + uvSize);

    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    int dstIndex = 0;
    for (int row = 0; row < height; row++) {
      final int rowOffset = row * yPlane.bytesPerRow;
      for (int col = 0; col < width; col++) {
        nv21[dstIndex++] = yPlane.bytes[rowOffset + col];
      }
    }

    final int chromaHeight = height ~/ 2;
    final int chromaWidth = width ~/ 2;
    for (int row = 0; row < chromaHeight; row++) {
      final int uRowOffset = row * uPlane.bytesPerRow;
      final int vRowOffset = row * vPlane.bytesPerRow;
      for (int col = 0; col < chromaWidth; col++) {
        final int uIndex = uRowOffset + (col * uPlane.bytesPerPixel!);
        final int vIndex = vRowOffset + (col * vPlane.bytesPerPixel!);
        nv21[dstIndex++] = vPlane.bytes[vIndex];
        nv21[dstIndex++] = uPlane.bytes[uIndex];
      }
    }

    return nv21;
  }

  Future<void> _processImage(CameraImage image) async {
    final FaceDetector? detector = _faceDetector;
    final CameraController? controller = _controller;
    if (detector == null || controller == null) return;

    _isBusy = true;

    try {
      final InputImage inputImage = _buildInputImage(image, controller);
      final List<Face> faces = await detector.processImage(inputImage);
      if (!mounted) return;

      if (faces.isEmpty) {
        if (_stage == _LivenessStage.waitingForBlink) {
          setState(() {
            _stage = _LivenessStage.waitingForFace;
          });
        }
        return;
      }

      final Face face = faces.first;
      if (_stage == _LivenessStage.waitingForFace) {
        setState(() {
          _stage = _LivenessStage.waitingForBlink;
        });
        _startChallengeTimeout();
      }

      final double? left = face.leftEyeOpenProbability;
      final double? right = face.rightEyeOpenProbability;
      final double yaw = face.headEulerAngleY ?? 0;

      if ((left == null || right == null) &&
          _stage == _LivenessStage.waitingForBlink) {
        return;
      }

      final bool eyesOpen = (left ?? 0) > 0.75 && (right ?? 0) > 0.75;
      final bool eyesClosed = (left ?? 1) < 0.30 && (right ?? 1) < 0.30;

      if (_stage == _LivenessStage.waitingForBlink && eyesOpen) {
        _eyesPreviouslyOpen = true;
      }

      if (_stage == _LivenessStage.waitingForBlink &&
          _eyesPreviouslyOpen &&
          eyesClosed) {
        setState(() {
          _stage = _LivenessStage.waitingForTurnLeft;
          _showRetry = false;
        });
        _startChallengeTimeout();
        return;
      }

      if (_stage == _LivenessStage.waitingForTurnLeft && yaw > 18) {
        setState(() {
          _stage = _LivenessStage.waitingForTurnRight;
        });
        _startChallengeTimeout();
        return;
      }

      if (_stage == _LivenessStage.waitingForTurnRight && yaw < -18) {
        await _completeLiveness();
      }
    } catch (e) {
      debugPrint('Liveness processing error: $e');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _completeLiveness() async {
    if (_stage != _LivenessStage.waitingForTurnRight) return;

    _timeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _showRetry = false;
        _showRetry = false;
      });
    }

    await _stopImageStreamIfNeeded();
    if (!mounted) return;

    setState(() {
      _stage = _LivenessStage.verifying;
    });

    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;

    setState(() {
      _stage = _LivenessStage.success;
    });

    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) return;

    Navigator.of(context).pop(<String, dynamic>{
      'verified': true,
      'message':
          'Blink aur left-right movement verify ho gaya / پلک اور بائیں دائیں حرکت کامیابی سے verify ہوگئی',
    });
  }

  Future<void> _retry() async {
    _timeoutTimer?.cancel();
    _eyesPreviouslyOpen = false;

    if (mounted) {
      setState(() {
        _showRetry = false;
        _stage = _LivenessStage.waitingForFace;
      });
    }

    await _startImageStream();
    _startChallengeTimeout();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusMessage() {
    switch (_stage) {
      case _LivenessStage.waitingForFace:
        return 'براہِ کرم چہرہ دائرے میں رکھیں / Keep your face inside the circle';
      case _LivenessStage.waitingForBlink:
        return 'آنکھیں جھپکائیں / Blink your eyes';
      case _LivenessStage.waitingForTurnLeft:
        return 'چہرہ بائیں موڑیں / Turn your face left';
      case _LivenessStage.waitingForTurnRight:
        return 'چہرہ دائیں موڑیں / Turn your face right';
      case _LivenessStage.verifying:
        return 'تصدیق جاری ہے / Verifying';
      case _LivenessStage.success:
        return 'تصدیق مکمل ہوگئی / Verification complete';
      case _LivenessStage.failed:
        return 'لائیونیس ناکام ہوگئی / Liveness failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: _deepGreen,
        body: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }

    final bool isVerifying = _stage == _LivenessStage.verifying;
    final bool isSuccess = _stage == _LivenessStage.success;
    final bool isFailed = _stage == _LivenessStage.failed;

    return Scaffold(
      backgroundColor: _deepGreen,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: _LivenessBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(
                children: <Widget>[
                  const Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text(
                      'لائیونیس تصدیق',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _gold,
                        fontSize: 36,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Jameel Noori Nastaleeq',
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '(Blink, then turn left and right)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 300,
                        height: 300,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSuccess
                                ? Colors.greenAccent
                                : (isFailed ? Colors.redAccent : _gold),
                            width: 4,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: _gold.withValues(alpha: 0.20),
                              blurRadius: 18,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: ClipOval(child: CameraPreview(_controller!)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Text(
                      _statusMessage(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontFamily: 'Jameel Noori Nastaleeq',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Attempts: $_attemptsUsed/$_maxAttempts',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (isVerifying)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.7,
                        color: _gold,
                      ),
                    ),
                  if (_showRetry) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _retry,
                      child: const Directionality(
                        textDirection: TextDirection.rtl,
                        child: Text(
                          'Retry / دوبارہ کریں',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (isFailed) ...<Widget>[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(<String, dynamic>{
                          'verified': false,
                          'message':
                              'Liveness failed after 3 attempts / لائیونیس 3 کوششوں کے بعد ناکام ہوگئی',
                        });
                      },
                      child: const Text(
                        'Back to signup / سائن اپ پر واپس جائیں',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    isFailed
                        ? 'No success state is saved on failure / ناکامی پر کوئی کامیاب حالت محفوظ نہیں ہوتی'
                        : 'Security check in progress / سیکیورٹی چیک جاری ہے',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller?.dispose();
    _faceDetector?.close();
    super.dispose();
  }
}

class _LivenessBackground extends StatelessWidget {
  const _LivenessBackground();

  static const Color _bgDeepGreen = Color(0xFF062517);
  static const Color _bgGreenMid = Color(0xFF11422B);
  static const Color _bgGreenTop = Color(0xFF0A3321);
  static const Color _bgGold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[_bgGreenTop, _bgGreenMid, _bgDeepGreen],
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _DigitalGridPainter(
              lineColor: Colors.white.withValues(alpha: 0.08),
              nodeColor: _bgGold.withValues(alpha: 0.10),
            ),
          ),
        ),
      ],
    );
  }
}

class _DigitalGridPainter extends CustomPainter {
  _DigitalGridPainter({required this.lineColor, required this.nodeColor});

  final Color lineColor;
  final Color nodeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.8;
    final Paint nodePaint = Paint()..color = nodeColor;
    const double gap = 30;

    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    for (double x = gap; x < size.width; x += gap * 2) {
      for (double y = gap; y < size.height; y += gap * 2) {
        canvas.drawCircle(Offset(x, y), 1.1, nodePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DigitalGridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.nodeColor != nodeColor;
  }
}
