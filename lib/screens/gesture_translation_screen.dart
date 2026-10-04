import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/detected_sign.dart';
import '../models/frame_landmarks.dart';
import '../providers/app_provider.dart';
import '../services/tflite_ai_service.dart';
import '../utils/constants.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/esenyas_app_bar.dart';
import '../widgets/hand_landmarks_painter.dart';

/// Gesture translation screen — the primary application feature.
///
/// Implements a bounded 4-second capture loop that matches the training
/// data format:
///   1. User taps Start → camera streams to hand_landmarker plugin.
///   2. Each 4-second window buffers [FrameLandmarks] from the landmark stream.
///   3. After 4 s → preprocessing + TFLite inference → append word if
///      confidence >= 60 %.
///   4. Loop repeats automatically until Stop is tapped.
class GestureTranslationScreen extends StatefulWidget {
  const GestureTranslationScreen({super.key});

  @override
  State<GestureTranslationScreen> createState() =>
      _GestureTranslationScreenState();
}

class _GestureTranslationScreenState
    extends State<GestureTranslationScreen> {
  // ── AI service ──
  final TFLiteAIService _aiService = TFLiteAIService();

  // ── Camera ──
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _permissionGranted = true; // optimistic until runtime check
  CameraLensDirection _lensDirection = CameraLensDirection.front;

  // ── Dynamic camera frame height ──
  static const double _cameraHeightMin = 140.0;
  static const double _cameraHeightMax = 400.0;
  double _cameraHeight = ESenyasDimens.cameraPreviewHeight;

  // ── Landmark buffer (populated from hand_landmarker stream) ──
  final List<FrameLandmarks> _frameBuffer = [];
  final ValueNotifier<List<Hand>> _liveHands = ValueNotifier<List<Hand>>([]);
  StreamSubscription<List<Hand>>? _landmarkSub;

  // ── Capture-loop state ──
  bool _isDetecting = false;
  Timer? _captureTimer;

  // ── Detection display ──
  String _currentSign = '';
  int _currentConfidence = 0;
  /// idle | scanning | detected
  String _detectionStatus = 'idle';

  // ── Sentence / session ──
  String _sentence = '';
  final List<DetectedSign> _sessionSigns = [];
  bool _savedToast = false;

  // ── Feedback (thumbs up / down) ──
  /// null = no feedback given yet, true = thumbs up, false = thumbs down
  bool? _feedbackValue;
  bool _feedbackSubmitted = false;

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
    // 1. Request CAMERA permission.
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _permissionGranted = false);
      return;
    }

    // 2. Load TFLite model + set up hand_landmarker plugin.
    await _aiService.initialize();

    // 3. Subscribe to the landmark stream BEFORE starting the image stream
    //    so no frames are lost.
    _landmarkSub = _aiService.handPlugin.landmarkStream.listen(_onLandmarks);

    // 4. Open the front camera.
    await _openCamera(_lensDirection);
  }

  Future<void> _openCamera(CameraLensDirection direction) async {
    final cameras = await availableCameras();
    final desc = cameras.firstWhere(
      (c) => c.lensDirection == direction,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();

    // Feed every camera frame to the hand landmarker (fire-and-forget).
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
        _lensDirection = direction;
      });
    }
  }

  // ──────────────────────────────────────────────────────────
  // Landmark stream callback
  // ──────────────────────────────────────────────────────────

  void _onLandmarks(List<Hand> hands) {
    _liveHands.value = hands;

    if (!_isDetecting) return;

    if (hands.isEmpty) {
      _frameBuffer.add(const FrameLandmarks.noHand());
    } else {
      // Convert hand_landmarker Hand/Landmark objects to raw doubles so
      // TFLiteAIService has no dependency on the plugin package.
      final rawHands = hands.map((hand) {
        return hand.landmarks
            .map((lm) => [lm.x, lm.y, lm.z])
            .toList();
      }).toList();

      _frameBuffer.add(FrameLandmarks(handDetected: true, hands: rawHands));
    }
  }

  // ──────────────────────────────────────────────────────────
  // Capture loop
  // ──────────────────────────────────────────────────────────

  void _startCaptureCycle() {
    _frameBuffer.clear();
    if (mounted) setState(() => _detectionStatus = 'scanning');
    _captureTimer = Timer(const Duration(seconds: 4), _onCaptureComplete);
  }

  Future<void> _onCaptureComplete() async {
    if (!_isDetecting || !mounted) return;

    // Snapshot the buffer and immediately start refilling for the next cycle.
    final buffer = List<FrameLandmarks>.from(_frameBuffer);

    final result = await _aiService.recognizeFromBuffer(buffer);

    if (!mounted || !_isDetecting) return;

    if (result != null) {
      setState(() {
        _currentSign = result.sign;
        _currentConfidence = result.confidence;
        _detectionStatus = 'detected';
        _sentence =
            _sentence.isEmpty ? result.sign : '$_sentence ${result.sign}';
      });
      _sessionSigns.add(result);
    } else {
      // Confidence below threshold — no word appended, stay in scanning state.
      setState(() {
        _detectionStatus = 'scanning';
        _currentSign = '';
        _currentConfidence = 0;
      });
    }

    // Immediately start the next 4-second cycle.
    if (_isDetecting && mounted) _startCaptureCycle();
  }

  // ──────────────────────────────────────────────────────────
  // Button handlers
  // ──────────────────────────────────────────────────────────

  void _handleStart() {
    setState(() {
      _sentence = '';
      _currentSign = '';
      _currentConfidence = 0;
      _isDetecting = true;
      _feedbackValue = null;
      _feedbackSubmitted = false;
    });
    _sessionSigns.clear();
    _startCaptureCycle();
  }

  void _handleStop() {
    _captureTimer?.cancel();
    setState(() {
      _isDetecting = false;
      _detectionStatus = 'idle';
    });
  }

  void _handleClear() {
    setState(() {
      _sentence = '';
      _currentSign = '';
      _currentConfidence = 0;
      _feedbackValue = null;
      _feedbackSubmitted = false;
    });
    _sessionSigns.clear();
  }

  void _handleSave() {
    if (_sessionSigns.isEmpty) return;
    context.read<AppProvider>().addHistoryItem(
          translatedSentence: _sentence,
          detectedSigns: List.from(_sessionSigns),
        );
    setState(() => _savedToast = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _savedToast = false);
    });
  }

  Future<void> _handleFlipCamera() async {
    if (!_cameraReady) return;
    final next = _lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    setState(() => _cameraReady = false);
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    _cameraController = null;
    await _openCamera(next);
  }

  bool get _canSave => !_isDetecting && _sessionSigns.isNotEmpty;
  bool get _canClear => !_isDetecting && _sentence.isNotEmpty;

  void _handleFeedback(bool isPositive) {
    setState(() {
      _feedbackValue = isPositive;
      _feedbackSubmitted = true;
    });
    // Auto-dismiss the "thank you" after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedbackSubmitted = false);
    });
  }

  // ──────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final darkMode = context.watch<AppProvider>().darkMode;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ESenyasAppBar(title: 'Pagsasalin ng Senyas'),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    color: darkMode
                        ? ESenyasColors.backgroundDark
                        : Colors.white,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // ── Camera preview (dynamic height) ──
                          _buildCameraSection(darkMode),

                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Detection status pill
                                _DetectionStatusPill(
                                  status: _detectionStatus,
                                  currentSign: _currentSign,
                                  confidence: _currentConfidence,
                                  darkMode: darkMode,
                                ),
                                const SizedBox(height: 8),

                                // ── Thumbs up / down feedback ──
                                if (_detectionStatus == 'detected' && _currentSign.isNotEmpty)
                                  _FeedbackRow(
                                    feedbackValue: _feedbackValue,
                                    feedbackSubmitted: _feedbackSubmitted,
                                    darkMode: darkMode,
                                    onThumbsUp: () => _handleFeedback(true),
                                    onThumbsDown: () => _handleFeedback(false),
                                  ),
                                const SizedBox(height: 12),

                                // Sentence output
                                _SentenceOutput(
                                  sentence: _sentence,
                                  isDetecting: _isDetecting,
                                  canClear: _canClear,
                                  onClear: _handleClear,
                                  darkMode: darkMode,
                                ),
                                const SizedBox(height: 12),

                                // Start / Stop buttons
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ActionButton(
                                        label: 'Simulan',
                                        icon: Icons.play_arrow,
                                        enabled: !_isDetecting && _cameraReady,
                                        color: ESenyasColors.accentGreen,
                                        disabledDark: darkMode,
                                        onTap: _handleStart,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _ActionButton(
                                        label: 'Itigil',
                                        icon: Icons.stop,
                                        enabled: _isDetecting,
                                        color: ESenyasColors.destructiveRed,
                                        disabledDark: darkMode,
                                        onTap: _handleStop,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Save button
                                SizedBox(
                                  width: double.infinity,
                                  height: ESenyasDimens.buttonHeight,
                                  child: ElevatedButton.icon(
                                    onPressed: _canSave ? _handleSave : null,
                                    icon: const Icon(Icons.save, size: 18),
                                    label: const Text('I-save sa Kasaysayan'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: darkMode
                                          ? ESenyasColors.primaryBlueDark
                                          : ESenyasColors.primaryBlue,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: darkMode
                                          ? ESenyasColors.gray700
                                          : const Color(0xFFE5E7EB),
                                      disabledForegroundColor: darkMode
                                          ? ESenyasColors.gray500
                                          : ESenyasColors.gray400,
                                      elevation: _canSave ? 1 : 0,
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
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Toast
                  if (_savedToast)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: ESenyasColors.accentGreen,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Na-save sa Kasaysayan',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const ESenyasBottomNavBar(currentIndex: 1),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Camera section widget
  // ──────────────────────────────────────────────────────────

  Widget _buildCameraSection(bool darkMode) {
    // Permission denied state
    if (!_permissionGranted) {
      return _CameraFallback(
        icon: Icons.no_photography,
        message: 'Kailangan ng pahintulot sa Camera.\n'
            'Buksan ang Settings para payagan.',
        darkMode: darkMode,
        action: TextButton(
          onPressed: openAppSettings,
          child: const Text('Buksan ang Settings'),
        ),
      );
    }

    // Loading / initialising state
    if (!_cameraReady || _cameraController == null) {
      return _CameraFallback(
        icon: Icons.camera_alt_outlined,
        message: 'Sinisimulan ang camera...',
        darkMode: darkMode,
        showSpinner: true,
      );
    }

    // Live CameraPreview with adjustable height
    return Column(
      children: [
        Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOut,
              height: _cameraHeight,
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
                            isFrontCamera:
                                _lensDirection == CameraLensDirection.front,
                            enabled: context
                                .watch<AppProvider>()
                                .showHandLandmarks,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // REC badge — reuses the "scanning/recording" visual from the old mock
            if (_isDetecting)
              Positioned(
                top: 10,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              top: 10,
              left: _isDetecting ? 76 : 12,
              child: HandDetectionBadge(handsNotifier: _liveHands),
            ),
            // Landmarks toggle button
            Positioned(
              top: 8,
              right: 46,
              child: Consumer<AppProvider>(
                builder: (context, provider, _) {
                  final active = provider.showHandLandmarks;
                  return GestureDetector(
                    onTap: () => provider.setShowHandLandmarks(!active),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
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
                            color: active
                                ? const Color(0xFF00E5FF)
                                : Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            active ? 'Points ON' : 'Points OFF',
                            style: TextStyle(
                              color: active
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white70,
                              fontSize: 10,
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
            // Camera flip button
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: _handleFlipCamera,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.flip_camera_android,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            // Frame size indicator (top-left, below REC)
            Positioned(
              bottom: 28,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_cameraHeight.round()}px',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        // ── Drag handle to resize camera frame ──
        GestureDetector(
          onVerticalDragUpdate: (details) {
            setState(() {
              _cameraHeight = (_cameraHeight + details.delta.dy)
                  .clamp(_cameraHeightMin, _cameraHeightMax);
            });
          },
          child: Container(
            width: double.infinity,
            height: 20,
            color: darkMode ? ESenyasColors.cardDark : const Color(0xFFF0F0F0),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: darkMode ? ESenyasColors.gray600 : ESenyasColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// _CameraFallback — shown while loading or if permission denied
// ──────────────────────────────────────────────────────────────

class _CameraFallback extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool darkMode;
  final bool showSpinner;
  final Widget? action;

  const _CameraFallback({
    required this.icon,
    required this.message,
    required this.darkMode,
    this.showSpinner = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ESenyasDimens.cameraPreviewHeight,
      width: double.infinity,
      color: darkMode ? ESenyasColors.cardDark : ESenyasColors.gray800,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showSpinner)
            const CircularProgressIndicator(color: Colors.white54)
          else
            Icon(icon, color: Colors.white54, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Thumbs up / down feedback widget
// ──────────────────────────────────────────────────────────────

class _FeedbackRow extends StatelessWidget {
  final bool? feedbackValue;
  final bool feedbackSubmitted;
  final bool darkMode;
  final VoidCallback onThumbsUp;
  final VoidCallback onThumbsDown;

  const _FeedbackRow({
    required this.feedbackValue,
    required this.feedbackSubmitted,
    required this.darkMode,
    required this.onThumbsUp,
    required this.onThumbsDown,
  });

  @override
  Widget build(BuildContext context) {
    // After submitting feedback, show a brief thank-you message
    if (feedbackSubmitted && feedbackValue != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(
              feedbackValue! ? Icons.thumb_up : Icons.thumb_down,
              size: 14,
              color: feedbackValue!
                  ? ESenyasColors.accentGreen
                  : ESenyasColors.destructiveRed,
            ),
            const SizedBox(width: 6),
            Text(
              feedbackValue!
                  ? 'Salamat sa iyong feedback!'
                  : 'Salamat! Pagbubutihin pa namin.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: darkMode ? ESenyasColors.gray400 : ESenyasColors.gray500,
              ),
            ),
          ],
        ),
      );
    }

    // Feedback buttons
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            'Tama ba ang resulta?',
            style: TextStyle(
              fontSize: 12,
              color: darkMode ? ESenyasColors.gray400 : ESenyasColors.gray500,
            ),
          ),
          const SizedBox(width: 12),
          _FeedbackButton(
            icon: Icons.thumb_up_outlined,
            activeIcon: Icons.thumb_up,
            label: 'Oo',
            isSelected: feedbackValue == true,
            color: ESenyasColors.accentGreen,
            darkMode: darkMode,
            onTap: onThumbsUp,
          ),
          const SizedBox(width: 8),
          _FeedbackButton(
            icon: Icons.thumb_down_outlined,
            activeIcon: Icons.thumb_down,
            label: 'Hindi',
            isSelected: feedbackValue == false,
            color: ESenyasColors.destructiveRed,
            darkMode: darkMode,
            onTap: onThumbsDown,
          ),
        ],
      ),
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final Color color;
  final bool darkMode;
  final VoidCallback onTap;

  const _FeedbackButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.color,
    required this.darkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : (darkMode ? ESenyasColors.gray700 : const Color(0xFFF3F4F6)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 14,
              color: isSelected
                  ? color
                  : (darkMode ? ESenyasColors.gray400 : ESenyasColors.gray500),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? color
                    : (darkMode ? ESenyasColors.gray400 : ESenyasColors.gray500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Private UI widgets — unchanged from original screen
// ──────────────────────────────────────────────────────────────

class _DetectionStatusPill extends StatelessWidget {
  final String status;
  final String currentSign;
  final int confidence;
  final bool darkMode;

  const _DetectionStatusPill({
    required this.status,
    required this.currentSign,
    required this.confidence,
    required this.darkMode,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    final String text;

    switch (status) {
      case 'detected':
        dotColor = ESenyasColors.accentGreen;
        text = 'Natukoy: "$currentSign" — $confidence%';
        break;
      case 'scanning':
        dotColor = const Color(0xFFFACC15); // yellow-400
        text = 'Naghahanap ng Kamay...';
        break;
      default:
        dotColor = ESenyasColors.gray300;
        text = 'Walang Natukoy na Kamay';
    }

    return Row(
      children: [
        _StatusDot(color: dotColor, pulsing: status == 'scanning'),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: darkMode ? const Color(0xFFD1D5DB) : ESenyasColors.gray600,
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool pulsing;

  const _StatusDot({required this.color, this.pulsing = false});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.pulsing
          ? _controller
          : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _SentenceOutput extends StatelessWidget {
  final String sentence;
  final bool isDetecting;
  final bool canClear;
  final VoidCallback onClear;
  final bool darkMode;

  const _SentenceOutput({
    required this.sentence,
    required this.isDetecting,
    required this.canClear,
    required this.onClear,
    required this.darkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Buong Pangungusap',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: darkMode ? const Color(0xFFD1D5DB) : ESenyasColors.gray700,
              ),
            ),
            if (canClear)
              GestureDetector(
                onTap: onClear,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh,
                      size: 11,
                      color: darkMode
                          ? ESenyasColors.gray500
                          : ESenyasColors.gray400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'I-clear',
                      style: TextStyle(
                        fontSize: 12,
                        color: darkMode
                            ? ESenyasColors.gray500
                            : ESenyasColors.gray400,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: darkMode ? ESenyasColors.cardDark : Colors.white,
            borderRadius:
                BorderRadius.circular(ESenyasDimens.borderRadiusMd),
            border: Border.all(color: ESenyasColors.accentGreen, width: 2),
          ),
          child: sentence.isNotEmpty
              ? RichText(
                  text: TextSpan(
                    text: sentence,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: ESenyasColors.accentGreen,
                      height: 1.3,
                    ),
                    children: isDetecting
                        ? [
                            WidgetSpan(
                              child: _BlinkingCursor(),
                              alignment: PlaceholderAlignment.baseline,
                              baseline: TextBaseline.alphabetic,
                            ),
                          ]
                        : null,
                  ),
                )
              : Center(
                  child: Text(
                    isDetecting
                        ? 'Naghihintay ng unang senyas...'
                        : 'Pindutin ang Simulan para magsimula',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: darkMode
                          ? ESenyasColors.gray600
                          : ESenyasColors.gray300,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      ],
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 22,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: ESenyasColors.accentGreen,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final Color color;
  final bool disabledDark;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.color,
    required this.disabledDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ESenyasDimens.buttonHeight,
      child: ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: disabledDark
              ? ESenyasColors.gray700
              : const Color(0xFFE5E7EB),
          disabledForegroundColor: disabledDark
              ? ESenyasColors.gray500
              : ESenyasColors.gray400,
          elevation: enabled ? 1 : 0,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(ESenyasDimens.borderRadiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
