import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/utils/system_ui.dart';
import 'core/utils/temp_cleaner.dart';
import 'providers/focus_mode.dart';
import 'providers/library_provider.dart';
import 'providers/privacy_settings.dart';
import 'providers/reading_settings.dart';
import 'providers/recent_provider.dart';
import 'providers/study_timer.dart';
import 'providers/tasks_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await pdfrxFlutterInitialize();
    SystemUi.init();

    // Runs in the background; removes old shared exports.
    TempCleaner.cleanOld();

    final prefs = await SharedPreferences.getInstance();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LibraryProvider(prefs)..init()),
          ChangeNotifierProvider(create: (_) => ReadingSettings(prefs)),
          ChangeNotifierProvider(create: (_) => StudyTimer(prefs)),
          ChangeNotifierProvider(create: (_) => FocusMode(prefs)),
          ChangeNotifierProvider(create: (_) => RecentProvider(prefs)),
          ChangeNotifierProvider(create: (_) => TasksProvider(prefs)),
          ChangeNotifierProvider(create: (_) => PrivacySettings(prefs)),
        ],
        child: const EduPdfApp(),
      ),
    );
  } catch (error, stack) {
    // Instead of a blank white screen, show what went wrong.
    runApp(_StartupError('$error\n\n$stack'));
  }
}

/// Shown only if the app fails while starting up.
class _StartupError extends StatelessWidget {
  const _StartupError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              'Startup error (please send this text):\n\n$message',
              style: const TextStyle(color: Colors.black, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
