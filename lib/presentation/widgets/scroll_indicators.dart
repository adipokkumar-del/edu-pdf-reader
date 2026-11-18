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
      if (mounted) setState(() => _visible = false);
    });

    void apply() {
      if (mounted) setState(() => _visible = true);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = (widget.dark ? Colors.white : AppColors.brownDark)
        .withValues(alpha: 0.45);
    Widget content = const SizedBox.shrink();

    if (widget.controller.isReady) {
      try {
        final doc = widget.controller.documentSize;
        final view = widget.controller.visibleRect;
        final inset = widget.inset;

        content = LayoutBuilder(builder: (context, box) {
          final children = <Widget>[];

          final trackH = box.maxHeight - inset.vertical;
          if (doc.height > view.height + 1 && trackH > 40) {
            final length =
                (trackH * view.height / doc.height).clamp(28.0, trackH).toDouble();
            final range = doc.height - view.height;
            final frac = range <= 0 ? 0.0 : (view.top / range).clamp(0.0, 1.0);
            children.add(Positioned(
              right: 2,
              top: inset.top + frac * (trackH - length),
              width: 3,
              height: length,
              child: _Thumb(color: color),
            ));
          }

          final trackW = box.maxWidth - inset.horizontal;
          if (view.width < doc.width * 0.97 && trackW > 40) {
            final length =
                (trackW * view.width / doc.width).clamp(28.0, trackW).toDouble();
            final range = doc.width - view.width;
            final frac = range <= 0 ? 0.0 : (view.left / range).clamp(0.0, 1.0);
            children.add(Positioned(
              bottom: inset.bottom + 2,
              left: inset.left + frac * (trackW - length),
              width: length,
              height: 3,
              child: _Thumb(color: color),
            ));
          }
          return Stack(children: children);
        });
      } catch (_) {
        content = const SizedBox.shrink();
      }
    }

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: content,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      );
}
