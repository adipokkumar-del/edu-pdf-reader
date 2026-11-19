import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/pdf_document_model.dart';
import '../../providers/recent_provider.dart';
import '../../data/services/file_actions.dart';
import 'pdf_thumbnail.dart';

class PdfFileTile extends StatelessWidget {
  const PdfFileTile({super.key, required this.document, required this.onTap});

  final PdfDocumentModel document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastPage = context.read<RecentProvider>().lastPage(document.path);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.brownDark.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                PdfThumbnail(
                  path: document.path,
                  sizeBytes: document.sizeBytes,
                  modified: document.modified,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${document.formattedSize}  •  ${document.formattedDate}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (lastPage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.play_circle_outline_rounded,
                                  size: 14, color: AppColors.brown),
                              const SizedBox(width: 4),
                              Text(
                                'Continue · page $lastPage',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brown,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert_rounded,
                      color: AppColors.textSecondary),
                  onSelected: (value) {
                    switch (value) {
                      case 'details':
                        FileActions.details(context, document);
                      case 'rename':
                        FileActions.rename(context, document);
                      case 'share':
                        FileActions.share(document);
                      case 'delete':
                        FileActions.delete(context, document);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'details', child: Text('Details')),
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'share', child: Text('Share')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
