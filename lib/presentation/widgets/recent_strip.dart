import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/recent_provider.dart';
import '../screens/reader_screen.dart';
import 'pdf_thumbnail.dart';

/// Compact row of recently opened PDFs, shown above the library.
class RecentStrip extends StatefulWidget {
  const RecentStrip({super.key});

  @override
  State<RecentStrip> createState() => _RecentStripState();
}

class _RecentStripState extends State<RecentStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = context.watch<RecentProvider>();

    final items = <(RecentEntry, FileStat)>[];
    for (final e in recent.entries) {
      final stat = File(e.path).statSync();
      if (stat.type != FileSystemEntityType.notFound) items.add((e, stat));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
          child: Row(
            children: [
              const Icon(Icons.history_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Recent',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: recent.clear,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 62,
          child: Scrollbar(
            controller: _scroll,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            thickness: 2,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final (entry, stat) = items[i];
                return _RecentCard(
                  entry: entry,
                  stat: stat,
                  page: recent.lastPage(entry.path),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReaderScreen(path: entry.path),
                    ),
                  ),
                  onRemove: () => recent.remove(entry.path),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.entry,
    required this.stat,
    required this.page,
    required this.onTap,
    required this.onRemove,
  });

  final RecentEntry entry;
  final FileStat stat;
  final int? page;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 172,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.divider),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onRemove,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                PdfThumbnail(
                  path: entry.path,
                  sizeBytes: stat.size,
                  modified: stat.modified,
                  width: 34,
                  height: 46,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                      if (page != null)
                        Text(
                          'Page $page',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
