import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/frame_landmarks.dart';
import '../providers/app_provider.dart';
import '../services/tflite_ai_service.dart';
import '../utils/constants.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/esenyas_app_bar.dart';
import '../widgets/hand_landmarks_painter.dart';

/// Testing Mode screen for evaluating gesture recognition accuracy.
///
/// Each "Next" cycle:
///   1. Picks a random expected gesture from [kTestGestures].
///   2. Runs a 4-second camera capture (same bounded-capture loop as the
///      main translation screen).
///   3. Runs TFLite inference on the captured buffer, measuring only the
///      preprocessing + inference time with a [Stopwatch].
///   4. Compares detected vs expected and updates session statistics.
class TestingModeScreen extends StatefulWidget {
  const TestingModeScreen({super.key});

  @override
  State<TestingModeScreen> createState() => _TestingModeScreenState();
}

class _TestingModeScreenState extends State<TestingModeScreen> {
  final _random = Random();

  // ── AI service ──
  final TFLiteAIService _aiService = TFLiteAIService();

  // ── Camera ──
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _permissionGranted = true;

  // ── Landmark buffer & live overlay ──
  final List<FrameLandmarks> _frameBuffer = [];
  final ValueNotifier<List<Hand>> _liveHands = ValueNotifier<List<Hand>>([]);
  StreamSubscription<List<Hand>>? _landmarkSub;

  // ── Capture state ──
  bool _isCapturing = false;
  Timer? _captureTimer;

  // ── Test display state ──
  String _expectedGesture = kTestGestures[0];
  String _detectedGesture = '—';
  bool _isCorrect = false;
  String _inferenceTime = '0.00';
  int _testCount = 0;
  int _correctCount = 0;
  bool _saved = false;
  String _captureStatus = 'idle'; // idle | capturing | done

  // ──────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initCameraAndService();
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _landmarkSub?.cancel();
    _liveHands.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _aiService.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────
  // Initialisation
  // ──────────────────────────────────────────────────────────

  Future<void> _initCameraAndService() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _permissionGranted = false);
      return;
    }

    await _aiService.initialize();
    _landmarkSub = _aiService.handPlugin.landmarkStream.listen(_onLandmarks);
    await _openCamera();
  }

  Future<void> _openCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    await controller.startImageStream((CameraImage image) {
      _aiService.handPlugin.processFrame(
        image,
        controller.description.sensorOrientation,
      );
    });

    if (mounted) {
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    }
  }

  // ──────────────────────────────────────────────────────────
  // Landmark callback
  // ──────────────────────────────────────────────────────────

  void _onLandmarks(List<Hand> hands) {
    _liveHands.value = hands;
    if (!_isCapturing) return;
    if (hands.isEmpty) {
      _frameBuffer.add(const FrameLandmarks.noHand());
    } else {
      final rawHands = hands.map((hand) {
        return hand.landmarks.map((lm) => [lm.x, lm.y, lm.z]).toList();
      }).toList();
      _frameBuffer.add(FrameLandmarks(handDetected: true, hands: rawHands));
    }
  }

  // ──────────────────────────────────────────────────────────
  // Button handlers
  // ──────────────────────────────────────────────────────────

  void _handleNextGesture() {
    if (_isCapturing || !_cameraReady) return;

    final idx = _random.nextInt(kTestGestures.length);
    setState(() {
      _expectedGesture = kTestGestures[idx];
      _detectedGesture = '—';
      _isCorrect = false;
      _inferenceTime = '0.00';
      _isCapturing = true;
      _saved = false;
      _captureStatus = 'capturing';
      _testCount++;
    });

    _frameBuffer.clear();
    _captureTimer = Timer(const Duration(seconds: 4), _onCaptureComplete);
  }

  Future<void> _onCaptureComplete() async {
    if (!mounted) return;
    final buffer = List<FrameLandmarks>.from(_frameBuffer);

    // Measure only preprocessing + inference, not the 4-second capture.
    final sw = Stopwatch()..start();
    final result = await _aiService.recognizeFromBuffer(buffer);
    sw.stop();

    if (!mounted) return;

    final detected = result?.sign ?? '(hindi natukoy)';
    final correct = detected == _expectedGesture;
    if (correct) setState(() => _correctCount++);

    setState(() {
      _detectedGesture = detected;
      _isCorrect = correct;
      _inferenceTime = (sw.elapsedMilliseconds / 1000).toStringAsFixed(3);
      _isCapturing = false;
      _captureStatus = 'done';
    });
  }

  void _handleRecordTest() {
    if (_captureStatus != 'done') return;
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  int get _accuracy =>
      _testCount > 0 ? (_correctCount / _testCount * 100).round() : 0;

  // ──────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ESenyasAppBar(title: 'Testing Mode'),
            Expanded(
              child: Container(
                color: Colors.white,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Research banner
                      Container(
                        color: ESenyasColors.gray800,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.science,
                                size: 18, color: ESenyasColors.accentGreen),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Research Data Collection',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Test #$_testCount · ${_isCapturing ? "Kumukuha (4s)..." : "Handa"}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: ESenyasColors.gray400,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Camera preview
                            _buildCameraSection(),
                            const SizedBox(height: 12),

                            // Detection status
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _isCapturing
                                        ? const Color(0xFFFACC15)
                                        : ESenyasColors.accentGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isCapturing
                                      ? 'Kumukuha ng 4-segundo na clip...'
                                      : 'Kamay ay Handa',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: ESenyasColors.gray600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Expected vs Detected
                            Row(
                              children: [
                                Expanded(
                                  child: _ComparisonBox(
                                    label: 'Expected',
                                    value: _expectedGesture,
                                    bgColor: ESenyasColors.surfaceBlueLight,
                                    borderColor: ESenyasColors.primaryBlue,
                                    textColor: ESenyasColors.primaryBlue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ComparisonBox(
                                    label: 'Detected',
                                    value: _detectedGesture,
                                    bgColor: _captureStatus == 'done'
                                        ? (_isCorrect
                                            ? const Color(0xFFF0FDF4)
                                            : const Color(0xFFFEF2F2))
                                        : const Color(0xFFF9FAFB),
                                    borderColor: _captureStatus == 'done'
                                        ? (_isCorrect
                                            ? ESenyasColors.accentGreen
                                            : const Color(0xFFF87171))
                                        : ESenyasColors.gray300,
                                    textColor: _captureStatus == 'done'
                                        ? (_isCorrect
                                            ? ESenyasColors.accentGreen
                                            : const Color(0xFFDC2626))
                                        : ESenyasColors.gray500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Result pills
                            const Text(
                              'Result',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: ESenyasColors.gray700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _ResultPill(
                                    label: 'Correct',
                                    icon: Icons.check,
                                    active: _captureStatus == 'done' &&
                                        _isCorrect,
                                    activeColor: ESenyasColors.accentGreen,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ResultPill(
                                    label: 'Incorrect',
                                    icon: Icons.close,
                                    active: _captureStatus == 'done' &&
                                        !_isCorrect,
                                    activeColor: ESenyasColors.destructiveRed,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Inference time (real Stopwatch measurement)
                            const Text(
                              'Inference Time',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: ESenyasColors.gray700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: 56,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9FAFB),
                                border: Border.all(
                                    color: const Color(0xFFE5E7EB), width: 2),
                                borderRadius: BorderRadius.circular(
                                    ESenyasDimens.borderRadiusMd),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    _inferenceTime,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: ESenyasColors.gray800,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    's',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: ESenyasColors.gray500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Session stats
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    ESenyasColors.primaryBlue,
                                    ESenyasColors.accentGreen,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(
                                    ESenyasDimens.borderRadiusMd),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Session Statistics',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _StatItem(
                                          value: '$_testCount',
                                          label: 'Tests'),
                                      _StatItem(
                                          value: '$_correctCount',
                                          label: 'Correct'),
                                      _StatItem(
                                          value: '$_accuracy%',
                                          label: 'Accuracy'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: ESenyasDimens.buttonHeight,
                                    child: ElevatedButton.icon(
                                      onPressed: _captureStatus == 'done'
                                          ? _handleRecordTest
                                          : null,
                                      icon: const Icon(Icons.save, size: 18),
                                      label: Text(
                                          _saved ? 'Saved!' : 'Record Test'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _saved
                                            ? ESenyasColors.accentGreen
                                            : ESenyasColors.primaryBlue,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            ESenyasColors.gray300,
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              ESenyasDimens.borderRadiusMd),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    height: ESenyasDimens.buttonHeight,
                                    child: ElevatedButton.icon(
                                      onPressed: _isCapturing || !_cameraReady
                                          ? null
                                          : _handleNextGesture,
                                      icon: const Icon(Icons.skip_next,
                                          size: 18),
                                      label: Text(_isCapturing
                                          ? 'Kumukuha...'
                                          : 'Next'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            ESenyasColors.accentGreen,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor:
                                            ESenyasColors.gray300,
                                        elevation: 1,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              ESenyasDimens.borderRadiusMd),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const ESenyasBottomNavBar(currentIndex: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraSection() {
    if (!_permissionGranted) {
      return Container(
        height: 200,
        width: double.infinity,
        color: ESenyasColors.gray800,
        child: const Center(
          child: Text(
            'Pahintulot sa Camera na kailangan.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    }

    if (!_cameraReady || _cameraController == null) {
      return Container(
        height: 200,
        width: double.infinity,
        color: ESenyasColors.gray800,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }

    final showLandmarks = context.watch<AppProvider>().showHandLandmarks;

    return ClipRRect(
      borderRadius: BorderRadius.circular(ESenyasDimens.borderRadiusMd),
      child: Stack(
        children: [
          SizedBox(
            height: 200,
            width: double.infinity,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize!.height,
                    height: _cameraController!.value.previewSize!.width,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_cameraController!),
                        HandSkeletonOverlay(
                          handsNotifier: _liveHands,
                          isFrontCamera: true,
                          enabled: showLandmarks,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // REC badge
          if (_isCapturing)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ESenyasColors.destructiveRed,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Hand detection status badge
          Positioned(
            top: 8,
            left: _isCapturing ? 72 : 8,
            child: HandDetectionBadge(handsNotifier: _liveHands),
          ),
          // Quick toggle for landmarks overlay
          Positioned(
            top: 8,
            right: 8,
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                final active = provider.showHandLandmarks;
                return GestureDetector(
                  onTap: () => provider.setShowHandLandmarks(!active),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF00E5FF)
                            : Colors.white24,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          active ? Icons.visibility : Icons.visibility_off,
                          size: 13,
                          color: active
                              ? const Color(0xFF00E5FF)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          active ? 'Landmarks ON' : 'Landmarks OFF',
                          style: TextStyle(
                            fontSize: 10,
                            color: active
                                ? const Color(0xFF00E5FF)
                                : Colors.white60,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Private UI widgets (visual style unchanged from original)
// ──────────────────────────────────────────────────────────────

class _ComparisonBox extends StatelessWidget {
  final String label;
  final String value;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;

  const _ComparisonBox({
    required this.label,
    required this.value,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: ESenyasColors.gray700,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: 2),
            borderRadius:
                BorderRadius.circular(ESenyasDimens.borderRadiusMd),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;

  const _ResultPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ESenyasDimens.buttonHeight,
      decoration: BoxDecoration(
        color: active ? activeColor : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(ESenyasDimens.borderRadiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 18,
              color: active ? Colors.white : ESenyasColors.gray300),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: active ? Colors.white : ESenyasColors.gray300,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
