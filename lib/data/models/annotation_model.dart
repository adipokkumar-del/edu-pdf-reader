import 'dart:ui';

/// How a stroke is inked. Stored as a small number in the saved data.
class StrokeKind {
  static const pen = 0; // solid, even line
  static const marker = 1; // wide, flat-tipped felt marker
  static const brush = 2; // soft brush whose width follows the hand speed
  static const highlighter = 3; // transparent, keeps the text underneath clear
}

class Stroke {
  const Stroke({
    required this.points,
    required this.colorValue,
    required this.width,
    this.opacity = 1.0,
    this.kind = StrokeKind.pen,
  });

  /// Points normalized to the page (0..1 on both axes), so strokes survive zooming.
  final List<Offset> points;
  final int colorValue;

  /// Stroke width as a fraction of page width.
  final double width;
  final double opacity;
  final int kind;

  Color get color => Color(colorValue);

  /// [aspect] is page height / page width; [radius] is in page-width units.
  bool isNear(Offset at, double aspect, double radius) {
    for (final p in points) {
      final dx = p.dx - at.dx;
      final dy = (p.dy - at.dy) * aspect;
      if (dx * dx + dy * dy <= radius * radius) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'c': colorValue,
        'w': width,
        'o': opacity,
        'k': kind,
        'p': [
          for (final o in points) ...[_round(o.dx), _round(o.dy)],
        ],
      };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final flat = (json['p'] as List).cast<num>();
    final legacyHighlighter = json['h'] as bool? ?? false;
    final opacity =
        (json['o'] as num?)?.toDouble() ?? (legacyHighlighter ? 0.35 : 1.0);
    return Stroke(
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
      colorValue: json['c'] as int,
      width: (json['w'] as num).toDouble(),
      opacity: opacity,
      kind: (json['k'] as int?) ??
          (legacyHighlighter || opacity <= 0.5
              ? StrokeKind.highlighter
              : StrokeKind.pen),
    );
  }

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;
}
