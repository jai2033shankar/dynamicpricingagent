import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Animated audio waveform visualizer for the voice input UI.
/// Shows sine waves that react to the listening state.
class WaveformVisualizer extends StatefulWidget {
  final bool isActive;
  final double height;
  final Color? color;

  const WaveformVisualizer({
    super.key,
    this.isActive = false,
    this.height = 80,
    this.color,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _amplitudeController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _amplitudeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void didUpdateWidget(WaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _amplitudeController.forward();
    } else if (!widget.isActive && oldWidget.isActive) {
      _amplitudeController.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _amplitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _amplitudeController]),
      builder: (context, _) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _WaveformPainter(
            phase: _controller.value * 2 * pi,
            amplitude: _amplitudeController.value,
            color: widget.color ?? AppTheme.accentBlue,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final Color color;

  _WaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final maxAmplitude = size.height * 0.35;
    final currentAmplitude = maxAmplitude * (0.15 + amplitude * 0.85);

    // Draw 3 layered waves with different frequencies and phases
    for (int layer = 0; layer < 3; layer++) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.15 + (2 - layer) * 0.15)
        ..strokeWidth = 2.5 - layer * 0.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      final frequency = 1.5 + layer * 0.7;
      final layerPhase = phase + layer * pi / 3;
      final layerAmplitude = currentAmplitude * (1.0 - layer * 0.25);

      for (double x = 0; x <= size.width; x += 1) {
        final normalizedX = x / size.width;
        final envelope = sin(normalizedX * pi);
        final y = centerY +
            sin(normalizedX * frequency * 2 * pi + layerPhase) *
                layerAmplitude *
                envelope;

        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, paint);
    }

    // Draw center glow when active
    if (amplitude > 0.1) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.05 * amplitude)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

      canvas.drawCircle(
        Offset(size.width / 2, centerY),
        40 * amplitude,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true;
}
