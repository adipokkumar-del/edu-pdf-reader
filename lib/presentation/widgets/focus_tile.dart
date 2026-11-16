import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/focus_mode.dart';

class FocusTile extends StatelessWidget {
  const FocusTile({super.key});

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusMode>();
    final needsAccess = focus.muteEnabled && !focus.hasAccess;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Mute notifications while reading',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            needsAccess
                ? 'Allow "Do Not Disturb access" for EduPDF, then come back.'
                : 'Silences notifications only while a PDF is open.',
          ),
          value: focus.muteEnabled,
          onChanged: focus.setMuteEnabled,
        ),
        if (needsAccess)
          TextButton(
            onPressed: focus.openAccessSettings,
            child: const Text('Open settings'),
          ),
      ],
    );
  }
}
