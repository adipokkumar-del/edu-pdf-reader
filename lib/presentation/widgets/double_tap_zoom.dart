import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// One-finger zoom: double-tap and keep the finger down, then drag.
/// Drag down to zoom in, up to zoom out. A plain double-tap steps the zoom.
///
/// It sits above the viewer. Normally it only watches touches (translucent),
/// so scrolling, pinching and text selection keep working. For a split second
/// after a first tap it captures touches to catch the second one.
class DoubleTapDragZoom extends StatefulWidget {
  const DoubleTapDragZoom({super.key, required this.controller});

  final PdfViewerController controller;

  @override
  State<DoubleTapDragZoom> createState() => _DoubleTapDragZoomState();
}

class _DoubleTapDragZoomState extends State<DoubleTapDragZoom> {
  static const _window = Duration(milliseconds: 300);
  static const _tapMax = Duration(milliseconds: 250);
  static const _slop = 18.0;
  static const _near = 60.0;

  final _active = <int>{};
  Timer? _timer;
  bool _armed = false;

  // First tap.
  bool _firstValid = false;
  bool _firstMoved = false;
  Offset _firstPos = Offset.zero;
  DateTime _firstAt = DateTime.now();
  Offset _lastTapPos = Offset.zero;

  // Drag zoom.
  int? _dragPointer;
  bool _dragged = false;
  Offset _focal = Offset.zero;
  Matrix4? _startMatrix;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    setState(() => _armed = true);
    _timer = Timer(_window, _disarm);
  }

  void _disarm() {
    _timer?.cancel();
    if (mounted && _armed) setState(() => _armed = false);
  }

  void _resetDrag() {
    _dragPointer = null;
    _startMatrix = null;
    _dragged = false;
  }

  /// Scales the view to [scale], keeping the point under [focal] fixed.
  void _zoomAbout(Matrix4 from, Offset focal, double scale, Duration duration) {
    final s0 = from.storage[0];
    if (s0 <= 0) return;
    final k = scale / s0;
    final tx = focal.dx - (focal.dx - from.storage[12]) * k;
    final ty = focal.dy - (focal.dy - from.storage[13]) * k;
    final next = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
    widget.controller.goTo(next, duration: duration);
  }

  void _down(PointerDownEvent e) {
    _active.add(e.pointer);
    if (_active.length > 1) {
      _firstValid = false;
      _resetDrag();
      return;
    }

    if (_armed) {
      if ((e.localPosition - _lastTapPos).distance <= _near &&
          widget.controller.isReady) {
        _timer?.cancel();
        _dragPointer = e.pointer;
        _dragged = false;
        _focal = e.localPosition;
        _startMatrix = Matrix4.copy(widget.controller.value);
        return;
      }
      _disarm();
    }

    _firstValid = true;
    _firstMoved = false;
    _firstPos = e.localPosition;
    _firstAt = DateTime.now();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer == _dragPointer) {
      final start = _startMatrix;
      if (start == null) return;
      final delta = e.localPosition - _focal;
      if (!_dragged && delta.distance < 10) return;
      _dragged = true;

      final s0 = start.storage[0];
      final scale = (s0 * math.exp(delta.dy / 220))
          .clamp(s0 * 0.35, math.min(s0 * 8, 12.0))
          .toDouble();
      _zoomAbout(start, _focal, scale, Duration.zero);
    } else if (_firstValid &&
        (e.localPosition - _firstPos).distance > _slop) {
      _firstMoved = true;
    }
  }

  void _up(PointerUpEvent e) {
    _active.remove(e.pointer);

    if (e.pointer == _dragPointer) {
      final wasDrag = _dragged;
      final start = _startMatrix;
      final focal = _focal;
      _resetDrag();
      _disarm();
      if (!wasDrag && start != null && widget.controller.isReady) {
        // Plain double-tap: step to the next zoom level around the tap.
        final target = widget.controller.getNextZoom(loop: true);
        _zoomAbout(
          Matrix4.copy(widget.controller.value),
          focal,
          target,
          const Duration(milliseconds: 200),
        );
      }
      return;
    }

    final quick = DateTime.now().difference(_firstAt) < _tapMax;
    if (_firstValid && !_firstMoved && quick && _active.isEmpty) {
      _lastTapPos = _firstPos;
      _arm();
    }
    _firstValid = false;
  }

  void _cancel(PointerCancelEvent e) {
    _active.remove(e.pointer);
    if (e.pointer == _dragPointer) _resetDrag();
    _firstValid = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: _armed ? HitTestBehavior.opaque : HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: const SizedBox.expand(),
    );
  }
}
