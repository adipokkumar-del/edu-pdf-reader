import 'dart:ui';

class Stroke {
  const Stroke({
    required this.points,
    required this.colorValue,
    required this.width,
    this.highlighter = false,
  });

  /// Points normalized to the page (0..1 on both axes), so strokes survive zooming.
  final List<Offset> points;
  final int colorValue;

  /// Stroke width as a fraction of the page width.
  final double width;
  final bool highlighter;

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
        'h': highlighter,
        'p': [
          for (final o in points) ...[_round(o.dx), _round(o.dy)],
        ],
      };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    final flat = (json['p'] as List).cast<num>();
    return Stroke(
      points: [
        for (var i = 0; i + 1 < flat.length; i += 2)
          Offset(flat[i].toDouble(), flat[i + 1].toDouble()),
      ],
      colorValue: json['c'] as int,
      width: (json['w'] as num).toDouble(),
      highlighter: json['h'] as bool? ?? false,
    );
  }

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;
}
