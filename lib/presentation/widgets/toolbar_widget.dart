import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/annotation_provider.dart';

class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({super.key});

  static const _tools = [
    (AnnotTool.pen, Icons.edit_rounded, 'Pen'),
    (AnnotTool.highlighter, Icons.highlight_rounded, 'Highlighter'),
    (AnnotTool.eraser, Icons.auto_fix_normal_rounded, 'Eraser'),
  ];

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AnnotationProvider>();

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: AppColors.brownDark.withValues(alpha: 0.25),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
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
                const SizedBox(width: 8),
                if (a.tool != AnnotTool.eraser)
                  for (final c in AnnotationProvider.palette)
                    _ColorDot(
                      color: c,
                      selected: a.color == c,
                      onTap: () => a.setColor(c),
                    ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Undo',
                  onPressed: a.canUndo ? a.undo : null,
                  icon: const Icon(Icons.undo_rounded),
                  color: AppColors.brownDark,
                ),
              ],
            ),
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
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: 28,
          height: 28,
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
    );
  }
}
