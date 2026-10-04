import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';

/// Standard MediaPipe 21 Hand Landmark indices:
///   0: Wrist
///   1-4: Thumb (CMC, MCP, IP, TIP)
///   5-8: Index finger (MCP, PIP, DIP, TIP)
///   9-12: Middle finger (MCP, PIP, DIP, TIP)
///   13-16: Ring finger (MCP, PIP, DIP, TIP)
///   17-20: Pinky (MCP, PIP, DIP, TIP)
const List<List<int>> _kHandConnections = [
  // Thumb
  [0, 1], [1, 2], [2, 3], [3, 4],
  // Index finger
  [0, 5], [5, 6], [6, 7], [7, 8],
  // Middle finger
  [9, 10], [10, 11], [11, 12],
  // Ring finger
  [13, 14], [14, 15], [15, 16],
  // Pinky
  [0, 17], [17, 18], [18, 19], [19, 20],
  // Palm knuckle base connections
  [5, 9], [9, 13], [13, 17],
];

/// Custom painter for rendering MediaPipe 21 hand landmarks and skeleton bones.
class HandSkeletonPainter extends CustomPainter {
  final List<Hand> hands;
  final bool isFrontCamera;

  HandSkeletonPainter({
    required this.hands,
    this.isFrontCamera = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty) return;

    final bonePaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.9) // Neon cyan
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final palmBonePaint = Paint()
      ..color = const Color(0xFF00B0FF).withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final jointPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;

    for (final hand in hands) {
      if (hand.landmarks.length < 21) continue;

      // Project normalized (0..1) landmarks to canvas coordinates
      final points = <Offset>[];
      for (final lm in hand.landmarks) {
        // Front-facing camera preview is mirrored horizontally
        final double px = isFrontCamera
            ? (1.0 - lm.x) * size.width
            : lm.x * size.width;
        final double py = lm.y * size.height;
        points.add(Offset(px, py));
      }

      // ── 1. Draw Skeleton Bones (Lines) ──
      for (final conn in _kHandConnections) {
        final int i1 = conn[0];
        final int i2 = conn[1];
        if (i1 >= points.length || i2 >= points.length) continue;

        // Use palm paint for palm base line
        final isPalm = (i1 == 5 && i2 == 9) ||
            (i1 == 9 && i2 == 13) ||
            (i1 == 13 && i2 == 17);

        canvas.drawLine(
          points[i1],
          points[i2],
          isPalm ? palmBonePaint : bonePaint,
        );
      }

      // ── 2. Draw Landmark Joints (Points) ──
      for (int i = 0; i < points.length; i++) {
        final pt = points[i];
        Color color;
        double radius = 3.8;

        if (i == 0) {
          // Wrist
          color = const Color(0xFFFF4081); // Magenta
          radius = 5.2;
        } else if (i == 4 || i == 8 || i == 12 || i == 16 || i == 20) {
          // Fingertips (Thumb, Index, Middle, Ring, Pinky)
          color = const Color(0xFFFF9100); // Amber / Coral
          radius = 5.0;
        } else if (i == 1 || i == 5 || i == 9 || i == 13 || i == 17) {
          // Knuckles / MCP joints
          color = const Color(0xFF00E676); // Neon Green
          radius = 4.2;
        } else {
          // PIP / DIP inter-finger joints
          color = const Color(0xFF00E5FF); // Cyan
          radius = 3.5;
        }

        // Outer glow
        glowPaint.color = color.withValues(alpha: 0.35);
        canvas.drawCircle(pt, radius + 2.5, glowPaint);

        // Colored joint dot
        jointPaint.color = color;
        canvas.drawCircle(pt, radius, jointPaint);

        // Core white center for crisp visibility
        jointPaint.color = Colors.white;
        canvas.drawCircle(pt, radius * 0.45, jointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HandSkeletonPainter oldDelegate) {
    return oldDelegate.hands != hands ||
        oldDelegate.isFrontCamera != isFrontCamera;
  }
}

/// Overlay widget that listens to a [ValueNotifier<List<Hand>>] and paints
/// landmarks smoothly without triggering full screen re-renders.
class HandSkeletonOverlay extends StatelessWidget {
  final ValueNotifier<List<Hand>> handsNotifier;
  final bool isFrontCamera;
  final bool enabled;

  const HandSkeletonOverlay({
    super.key,
    required this.handsNotifier,
    this.isFrontCamera = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();

    return ValueListenableBuilder<List<Hand>>(
      valueListenable: handsNotifier,
      builder: (context, hands, _) {
        if (hands.isEmpty) return const SizedBox.shrink();
        return CustomPaint(
          size: Size.infinite,
          painter: HandSkeletonPainter(
            hands: hands,
            isFrontCamera: isFrontCamera,
          ),
        );
      },
    );
  }
}

/// Live badge indicating whether any hands are detected in the camera feed.
class HandDetectionBadge extends StatelessWidget {
  final ValueNotifier<List<Hand>> handsNotifier;

  const HandDetectionBadge({super.key, required this.handsNotifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Hand>>(
      valueListenable: handsNotifier,
      builder: (context, hands, _) {
        final detected = hands.isNotEmpty;
        final count = hands.length;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: detected
                ? const Color(0xD000B248)
                : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: detected
                  ? const Color(0xFF69F0AE)
                  : Colors.white.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: detected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.3),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                detected ? Icons.front_hand : Icons.front_hand_outlined,
                size: 12,
                color: Colors.white,
              ),
              const SizedBox(width: 5),
              Text(
                detected
                    ? (count == 1 ? '1 Kamay Nakita' : '$count Kamay Nakita')
                    : 'Naghahanap...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
