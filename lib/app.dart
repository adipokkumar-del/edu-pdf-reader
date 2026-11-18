import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/native_bridge.dart';
import 'presentation/screens/main_shell.dart';
import 'presentation/screens/reader_screen.dart';

class EduPdfApp extends StatefulWidget {
  const EduPdfApp({super.key});

  @override
  State<EduPdfApp> createState() => _EduPdfAppState();
}

class _EduPdfAppState extends State<EduPdfApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    NativeBridge.onOpenPdf = _open;
    NativeBridge.listen();

    // A PDF that launched the app ("Open with" from a cold start).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final path = await NativeBridge.initialPdf();
      if (path != null) _open(path);
    });
  }

  void _open(String path) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
    navigator.push(
      MaterialPageRoute(builder: (_) => ReaderScreen(path: path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EduPDF Reader',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainShell(),
    );
  }
}
