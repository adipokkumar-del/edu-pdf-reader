import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/reading_settings.dart';
import '../../providers/study_timer.dart';
import 'focus_tile.dart';

String _clock(int seconds) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(seconds ~/ 60)}:${two(seconds % 60)}';
}

/// Sliding panel with reading tools.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.annotating,
    required this.onClose,
    required this.onSearch,
    required this.onBookmarks,
    required this.onAnnotate,
    required this.onNotes,
    required this.onExportPdf,
    required this.onExportNotes,
    required this.onExtractText,
  });

  final bool annotating;
  final VoidCallback onClose;
  final VoidCallback onSearch;
  final VoidCallback onBookmarks;
  final VoidCallback onAnnotate;
  final VoidCallback onNotes;
  final VoidCallback onExportPdf;
  final VoidCallback onExportNotes;
  final VoidCallback onExtractText;

  static const _modeLabels = {
    ReadingMode.normal: 'Normal',
    ReadingMode.warm: 'Warm',
    ReadingMode.dark: 'Dark',
    ReadingMode.ink: 'Ink paper',
  };

  static const _grainLabels = {
    GrainType.none: 'None',
    GrainType.fine: 'Fine',
    GrainType.medium: 'Medium',
    GrainType.coarse: 'Coarse',
    GrainType.fibre: 'Fibre',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ReadingSettings>();
    final dark = s.mode == ReadingMode.dark;
    final theme = dark
        ? ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.brown,
              brightness: Brightness.dark,
            ),
          )
        : Theme.of(context);

    return Theme(
      data: theme,
      child: Material(
        color: dark ? const Color(0xFF1B1411) : Colors.white,
        elevation: 12,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reading tools',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide panel',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClose,
                  ),
                ],
              ),
              _ActionTile(
                icon: Icons.draw_outlined,
                label: annotating ? 'Stop annotating' : 'Annotate',
                onTap: onAnnotate,
              ),
              _ActionTile(
                icon: Icons.search_rounded,
                label: 'Search',
                onTap: onSearch,
              ),
              _ActionTile(
                icon: Icons.copy_all_rounded,
                label: 'Extract page text',
                onTap: onExtractText,
              ),
              _ActionTile(
                icon: Icons.bookmarks_outlined,
                label: 'Bookmarks',
                onTap: onBookmarks,
              ),
              _ActionTile(
                icon: Icons.sticky_note_2_outlined,
                label: 'Notes',
                onTap: onNotes,
              ),
              const Divider(height: 28),
              const _Heading('Export'),
              _ActionTile(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Share annotated PDF',
                onTap: onExportPdf,
              ),
              _ActionTile(
                icon: Icons.text_snippet_outlined,
                label: 'Share notes (.txt)',
                onTap: onExportNotes,
              ),
              const Divider(height: 28),
              const _Heading('Display'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in ReadingMode.values)
                    ChoiceChip(
                      label: Text(_modeLabels[m]!),
                      selected: s.mode == m,
                      onSelected: (_) => s.setMode(m),
                    ),
                ],
              ),
              _SliderRow(
                label: 'Warmth',
                value: s.warmth,
                onChanged: s.mode == ReadingMode.normal ? null : s.setWarmth,
              ),
              _SliderRow(
                label: 'Brightness',
                value: s.brightness,
                min: 0.4,
                onChanged: s.setBrightness,
              ),
              _SliderRow(
                label: 'Scroll ${s.scrollSpeed.toStringAsFixed(1)}×',
                value: ((s.scrollSpeed - 1) / 4).clamp(0.0, 1.0),
                onChanged: (v) => s.setScrollSpeed(1 + v * 4),
              ),
              const Divider(height: 28),
              const _Heading('Page texture'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final g in GrainType.values)
                    ChoiceChip(
                      label: Text(_grainLabels[g]!),
                      selected: s.grain == g,
                      onSelected: (_) => s.setGrain(g),
                    ),
                ],
              ),
              if (s.grain != GrainType.none)
                _SliderRow(
                  label: 'Strength',
                  value: s.grainStrength,
                  onChanged: s.setGrainStrength,
                ),
              const Divider(height: 28),
              const _Heading('Study timer'),
              const _TimerSection(),
              const Divider(height: 28),
              const _Heading('Focus'),
              const FocusTile(),
              const SizedBox(height: 12),
              const Text(
                'Tip: long-press the round button and drag it anywhere. '
                'Tap the page once to hide or show the bars.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.brown),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      onTap: onTap,
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
  });

  final String label;
  final double value;
  final double min;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 78, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, 1.0),
            min: min,
            max: 1,
            activeColor: AppColors.brown,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _TimerSection extends StatelessWidget {
  const _TimerSection();

  @override
  Widget build(BuildContext context) {
    final t = context.watch<StudyTimer>();
    final focus = t.phase == TimerPhase.focus;
    final studiedMinutes = t.studiedSeconds ~/ 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final m in StudyTimer.focusOptions)
              ChoiceChip(
                label: Text('$m min'),
                selected: t.focusMinutes == m,
                onSelected: t.running ? null : (_) => t.setFocusMinutes(m),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              Text(
                _clock(t.remaining),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.brown,
                    ),
              ),
              Text(
                focus ? 'Focus' : 'Break',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: t.running ? t.pause : t.start,
              icon: Icon(
                  t.running ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(t.running ? 'Pause' : 'Start'),
            ),
            IconButton(
              tooltip: 'Reset',
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: t.reset,
            ),
            IconButton(
              tooltip: focus ? 'Skip to break' : 'Skip to focus',
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: t.skip,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Today: ${studiedMinutes}m  •  ${t.sessions} session${t.sessions == 1 ? '' : 's'}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Small countdown shown over the page while the timer is running.
class TimerPill extends StatelessWidget {
  const TimerPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<StudyTimer>();
    if (!t.running) return const SizedBox.shrink();

    return Material(
      color: AppColors.brownDark.withValues(alpha: 0.9),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                t.phase == TimerPhase.focus
                    ? Icons.timer_outlined
                    : Icons.free_breakfast_outlined,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                _clock(t.remaining),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
