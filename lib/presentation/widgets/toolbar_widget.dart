import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/annotation_provider.dart';

class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({super.key});

  static const _tools = [
    (AnnotTool.ball, Icons.edit_rounded, 'Ball pen'),
    (AnnotTool.fine, Icons.mode_edit_outline_rounded, 'Fine pen'),
    (AnnotTool.marker, Icons.brush_rounded, 'Marker'),
    (AnnotTool.highlighter, Icons.highlight_rounded, 'Highlighter'),
    (AnnotTool.eraser, Icons.auto_fix_normal_rounded, 'Eraser'),
  ];

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AnnotationProvider>();
    final eraser = a.tool == AnnotTool.eraser;

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: AppColors.brownDark.withValues(alpha: 0.25),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ToolButton(
                      icon: Icons.pan_tool_alt_rounded,
                      label: 'Move / zoom',
                      selected: a.hand,
                      onTap: () => a.setHand(!a.hand),
                    ),
                    for (final (tool, icon, label) in _tools)
                      _ToolButton(
                        icon: icon,
                        label: label,
                        selected: !a.hand && a.tool == tool,
                        onTap: () => a.setTool(tool),
                      ),
                    IconButton(
                      tooltip: 'Undo',
                      onPressed: a.canUndo ? a.undo : null,
                      icon: const Icon(Icons.undo_rounded),
                      color: AppColors.brownDark,
                    ),
                  ],
                ),
              ),
              if (eraser)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Touch a stroke to remove it',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                Row(
                  children: [
                    for (var i = 0; i < a.palette.length; i++)
                      _ColorDot(
                        color: a.palette[i],
                        selected: a.colorIndex == i,
                        onTap: () => a.setColorIndex(i),
                        onEdit: () async {
                          final picked =
                              await showColorEditor(context, a.palette[i]);
                          if (picked != null) a.editPaletteColor(i, picked);
                        },
                      ),
                    Expanded(
                      child: Slider(
                        value: a.sizeScale.clamp(0.5, 2.5),
                        min: 0.5,
                        max: 2.5,
                        activeColor: AppColors.brown,
                        onChanged: a.setSize,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: selected ? AppColors.brown : Colors.transparent,
        foregroundColor: selected ? Colors.white : AppColors.brownDark,
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hold to change this colour',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.brownDark : AppColors.brownLight,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small HSV colour editor. Returns null when cancelled.
Future<Color?> showColorEditor(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) {
      var hsv = HSVColor.fromColor(initial);
      return StatefulBuilder(
        builder: (ctx, setState) {
          Widget row(String label, double value, double max,
              ValueChanged<double> onChanged) {
            return Row(
              children: [
                SizedBox(width: 82, child: Text(label)),
                Expanded(
                  child: Slider(
                    value: value.clamp(0.0, max),
                    max: max,
                    activeColor: AppColors.brown,
                    onChanged: (v) => setState(() => onChanged(v)),
                  ),
                ),
              ],
            );
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Edit colour'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: hsv.toColor(),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider),
                  ),
                ),
                const SizedBox(height: 8),
                row('Hue', hsv.hue, 360, (v) => hsv = hsv.withHue(v)),
                row('Saturation', hsv.saturation, 1,
                    (v) => hsv = hsv.withSaturation(v)),
                row('Brightness', hsv.value, 1, (v) => hsv = hsv.withValue(v)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, hsv.toColor()),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}
