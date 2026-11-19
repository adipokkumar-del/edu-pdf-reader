import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/temp_cleaner.dart';
import '../../providers/privacy_settings.dart';
import 'default_pdf_dialog.dart';

/// ⋮ menu in the Library: default app, privacy screen, temporary files.
class LibraryMenu extends StatelessWidget {
  const LibraryMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final privacy = context.watch<PrivacySettings>();

    return PopupMenuButton<String>(
      tooltip: 'More',
      color: Colors.white,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'default':
            DefaultPdfDialog.show(context);
          case 'secure':
            privacy.setSecure(!privacy.secure);
          case 'clear':
            {
              final count = await TempCleaner.clearAll();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text('Cleared $count temporary item(s)')),
                );
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'default',
          child: Text('Set as default PDF app'),
        ),
        CheckedPopupMenuItem(
          value: 'secure',
          checked: privacy.secure,
          child: const Text('Privacy screen'),
        ),
        const PopupMenuItem(
          value: 'clear',
          child: Text('Clear temporary files'),
        ),
      ],
    );
  }
}
