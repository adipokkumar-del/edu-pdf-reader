import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReadingMode { normal, warm, dark, ink }

enum GrainType { none, fine, medium, coarse, fibre }

/// App-wide display settings: reading mode, warmth, brightness, paper grain.
class ReadingSettings extends ChangeNotifier {
  ReadingSettings(this._prefs) {
    mode = ReadingMode.values.firstWhere(
      (m) => m.name == _prefs.getString('rs_mode'),
      orElse: () => ReadingMode.normal,
    );
    grain = GrainType.values.firstWhere(
      (g) => g.name == _prefs.getString('rs_grain'),
      orElse: () => GrainType.none,
    );
    warmth = _prefs.getDouble('rs_warmth') ?? 0.4;
    brightness = _prefs.getDouble('rs_brightness') ?? 1.0;
    grainStrength = _prefs.getDouble('rs_grain_strength') ?? 0.5;
    scrollSpeed =
        (_prefs.getDouble('rs_scroll_speed') ?? 1.7).clamp(1.0, 3.0).toDouble();
    panelLeft = _prefs.getBool('rs_panel_left') ?? false;
    handleFx = _prefs.getDouble('rs_handle_fx') ?? 1.0;
    handleFy = _prefs.getDouble('rs_handle_fy') ?? 0.5;
    scrollSpeed =
        (_prefs.getDouble('rs_scroll_speed2') ?? 3.0).clamp(1.0, 5.0).toDouble();
    _buildGrain();
  }

  final SharedPreferences _prefs;

  ReadingMode mode = ReadingMode.normal;
  GrainType grain = GrainType.none;
  double warmth = 0.4;
  double brightness = 1.0;
  double grainStrength = 0.5;
  double scrollSpeed = 2.2;
  bool panelLeft = false;
  double handleFx = 1.0;
  double handleFy = 0.5;

  ui.Image? _grainImage;

  // ---- Setters ------------------------------------------------------------

  void setMode(ReadingMode value) {
    mode = value;
    _prefs.setString('rs_mode', value.name);
    notifyListeners();
    _buildGrain(); // grain colour depends on dark/light
  }

  void setWarmth(double value) {
    warmth = value;
    _prefs.setDouble('rs_warmth', value);
    notifyListeners();
  }

  void setBrightness(double value) {
    brightness = value;
    _prefs.setDouble('rs_brightness', value);
    notifyListeners();
  }

  void setGrain(GrainType value) {
    grain = value;
    _prefs.setString('rs_grain', value.name);
    notifyListeners();
    _buildGrain();
  }

  void setGrainStrength(double value) {
    grainStrength = value;
    _prefs.setDouble('rs_grain_strength', value);
    notifyListeners();
  }

  // ---- Colour filter for the page images ----------------------------------

  void setScrollSpeed(double value) {
    scrollSpeed = value.clamp(1.0, 5.0).toDouble();
    _prefs.setDouble('rs_scroll_speed2', scrollSpeed);
    notifyListeners();
  }

  /// Where the round panel button sits, as fractions of the free area.
  /// Does not notify: the reader redraws itself after a drag.
  void setHandle(double fx, double fy) {
    handleFx = fx.clamp(0.0, 1.0).toDouble();
    handleFy = fy.clamp(0.0, 1.0).toDouble();
    _prefs.setDouble('rs_handle_fx', handleFx);
    _prefs.setDouble('rs_handle_fy', handleFy);
  }

  void setPanelLeft(bool value) {
    panelLeft = value;
    _prefs.setBool('rs_panel_left', value);
    notifyListeners();
  }

  Color get viewerBackground => switch (mode) {
        ReadingMode.normal => const Color(0xFFF3EBE7),
        ReadingMode.warm => const Color(0xFFEADFD2),
        ReadingMode.dark => const Color(0xFF0F0C0A),
        ReadingMode.ink => const Color(0xFFD9D2C3),
      };

  ColorFilter? get pageFilter {
    if (mode == ReadingMode.normal && brightness >= 0.999) return null;

    var m = _identity;
    if (mode == ReadingMode.dark) m = _darkMatrix;
    if (mode == ReadingMode.ink) m = _inkMatrix;
    if (mode != ReadingMode.normal) {
      m = _chain(m, _diag(1, 1 - 0.12 * warmth, 1 - 0.5 * warmth));
    }
    if (brightness < 0.999) {
      m = _chain(m, _diag(brightness, brightness, brightness));
    }
    return ColorFilter.matrix(m);
  }

  static const List<double> _identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  // Soft invert: white page -> very dark brown-black, black text -> light grey.
  static const List<double> _darkMatrix = [
    -0.82, 0, 0, 0, 222, //
    0, -0.82, 0, 0, 222,
    0, 0, -0.82, 0, 222,
    0, 0, 0, 1, 0,
  ];

  // Greyscale + a little contrast, then a cream paper tone.
  static const List<double> _grayMatrix = [
    0.2445, 0.8225, 0.083, 0, -19.2, //
    0.2445, 0.8225, 0.083, 0, -19.2,
    0.2445, 0.8225, 0.083, 0, -19.2,
    0, 0, 0, 1, 0,
  ];
  static final List<double> _inkMatrix =
      _chain(_grayMatrix, _diag(0.97, 0.95, 0.88));

  static List<double> _diag(double r, double g, double b) => [
        r, 0, 0, 0, 0, //
        0, g, 0, 0, 0,
        0, 0, b, 0, 0,
        0, 0, 0, 1, 0,
      ];

  /// Returns the matrix that applies [a] first, then [b].
  static List<double> _chain(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var v = 0.0;
        for (var k = 0; k < 4; k++) {
          v += b[r * 5 + k] * a[k * 5 + c];
        }
        if (c == 4) v += b[r * 5 + 4];
        out[r * 5 + c] = v;
      }
    }
    return out;
  }

  // ---- Paper grain --------------------------------------------------------

  /// Passed to PdfViewerParams.pagePaintCallbacks.
  void paintGrain(Canvas canvas, Rect pageRect, PdfPage page) {
    final image = _grainImage;
    if (image == null || grainStrength <= 0) return;
    final paint = Paint()
      ..shader = ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      )
      ..colorFilter = ColorFilter.mode(
        Color.fromRGBO(255, 255, 255, grainStrength),
        BlendMode.modulate,
      );
    canvas.drawRect(pageRect, paint);
  }

  Future<void> _buildGrain() async {
    final type = grain;
    final light = mode == ReadingMode.dark;
    if (type == GrainType.none) {
      _grainImage = null;
      notifyListeners();
      return;
    }
    final image = await _makeTile(type, light);
    if (type != grain || light != (mode == ReadingMode.dark)) return;
    _grainImage = image;
    notifyListeners();
  }

  Future<ui.Image> _makeTile(GrainType type, bool light) {
    const size = 256;
    final rnd = math.Random(type.index * 31 + 5);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    );
    final grey = light ? 0xE0 : 0x55;
    final paint = Paint()..isAntiAlias = true;

    if (type == GrainType.fibre) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 170; i++) {
        final x = rnd.nextDouble() * size;
        final y = rnd.nextDouble() * size;
        final len = 5 + rnd.nextDouble() * 14;
        final angle = rnd.nextDouble() * math.pi * 2;
        paint.color = Color.fromRGBO(
            grey, grey, grey, 0.12 + rnd.nextDouble() * 0.16);
        canvas.drawLine(
          Offset(x, y),
          Offset(x + math.cos(angle) * len, y + math.sin(angle) * len),
          paint,
        );
      }
    } else {
      final (count, rMin, rMax, aMin, aMax) = switch (type) {
        GrainType.fine => (1800, 0.35, 0.7, 0.10, 0.30),
        GrainType.medium => (900, 0.6, 1.1, 0.12, 0.32),
        _ => (380, 1.0, 1.8, 0.12, 0.30),
      };
      for (var i = 0; i < count; i++) {
        paint.color = Color.fromRGBO(
            grey, grey, grey, aMin + rnd.nextDouble() * (aMax - aMin));
        canvas.drawCircle(
          Offset(rnd.nextDouble() * size, rnd.nextDouble() * size),
          rMin + rnd.nextDouble() * (rMax - rMin),
          paint,
        );
      }
    }
    return recorder.endRecording().toImage(size, size);
  }
}
