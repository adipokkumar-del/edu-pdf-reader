import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/constants/app_colors.dart';

/// Thin, translucent scroll indicators for the PDF (vertical, and horizontal
/// when zoomed in). They appear while you scroll and fade away afterwards.
class ScrollIndicators extends StatefulWidget {
  const ScrollIndicators({
    super.key,
    required this.controller,
    this.inset = EdgeInsets.zero,
    this.dark = false,
  });

  final PdfViewerController controller;
  final EdgeInsets inset;
  final bool dark;

  @override
  State<ScrollIndicators> createState() => _ScrollIndicatorsState();
}

class _ScrollIndicatorsState extends State<ScrollIndicators> {
  Timer? _hide;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onMove);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onMove);
    _hide?.cancel();
    super.dispose();
  }

  void _onMove() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _visible) setState(() => _visible = false);
    });

    // Only rebuild when the indicators actually have to appear.
    if (_visible) return;
    void show() {
      if (mounted) setState(() => _visible = true);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => show());
    } else {
      show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = (widget.dark ? Colors.white : AppColors.brownDark)
        .withValues(alpha: 0.45);

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: CustomPaint(
          size: Size.infinite,
          painter: _IndicatorPainter(
            controller: widget.controller,
            color: color,
            inset: widget.inset,
          ),
        ),
      ),
    );
  }
}

/// Repaints on every viewer movement without rebuilding any widget.
class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({
    required this.controller,
    required this.color,
    required this.inset,
  }) : super(repaint: controller);

  final PdfViewerController controller;
  final Color color;
  final EdgeInsets inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isReady) return;
    try {
      final doc = controller.documentSize;
      final view = controller.visibleRect;
      final paint = Paint()..color = color;

      final trackH = size.height - inset.vertical;
      if (doc.height > view.height + 1 && trackH > 40) {
        final length =
            (trackH * view.height / doc.height).clamp(28.0, trackH).toDouble();
        final range = doc.height - view.height;
        final frac = range <= 0 ? 0.0 : (view.top / range).clamp(0.0, 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              size.width - 5,
              inset.top + frac * (trackH - length),
              3,
              length,
            ),
            const Radius.circular(3),
          ),
          paint,
        );
      }

      final trackW = size.width - inset.horizontal;
      if (view.width < doc.width * 0.97 && trackW > 40) {
        final length =
            (trackW * view.width / doc.width).clamp(28.0, trackW).toDouble();
        final range = doc.width - view.width;
        final frac = range <= 0 ? 0.0 : (view.left / range).clamp(0.0, 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              inset.left + frac * (trackW - length),
              size.height - inset.bottom - 5,
              length,
              3,
            ),
            const Radius.circular(3),
          ),
          paint,
        );
      }
    } catch (_) {
      // The viewer is not ready yet; nothing to draw.
    }
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) =>
      old.color != color || old.inset != inset;
}
