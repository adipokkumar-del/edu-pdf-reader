import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/constants/app_colors.dart';

/// Draggable scroll handle on the right edge (like Google Drive's PDF reader).
/// It shows the current page number, is translucent, and hides by itself
/// a moment after scrolling stops.
class AutoHideScrollThumb extends StatefulWidget {
  const AutoHideScrollThumb({
    super.key,
    required this.controller,
    this.dark = false,
  });

  final PdfViewerController controller;
  final bool dark;

  @override
  State<AutoHideScrollThumb> createState() => _AutoHideScrollThumbState();
}

class _AutoHideScrollThumbState extends State<AutoHideScrollThumb> {
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
    _hide = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && _visible) setState(() => _visible = false);
    });
    if (_visible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_visible) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.dark ? Colors.white : AppColors.brownDark;
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: Stack(
          children: [
            PdfViewerScrollThumb(
              controller: widget.controller,
              orientation: ScrollbarOrientation.right,
              thumbSize: const Size(44, 30),
              thumbBuilder: (context, thumbSize, pageNumber, controller) =>
                  Container(
                decoration: BoxDecoration(
                  color: base.withValues(alpha: 0.35),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(15),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  pageNumber?.toString() ?? '',
                  style: TextStyle(
                    color: widget.dark ? Colors.black87 : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
