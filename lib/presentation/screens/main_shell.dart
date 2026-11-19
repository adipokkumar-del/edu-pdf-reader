import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/system_ui.dart';
import '../widgets/default_pdf_dialog.dart';
import 'home_screen.dart';
import 'tasks_screen.dart';

/// Main page: Library and Notes tabs.
/// A tap on an empty area hides or shows the system bars.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // First launch only: offer to make this the default PDF app.
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) DefaultPdfDialog.promptOnce(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUi.style(),
      child: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: SystemUi.toggle,
          child: IndexedStack(
            index: _index,
            children: const [HomeScreen(), TasksScreen()],
          ),
        ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: AppColors.brownSurface,
            height: 64,
            labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon:
                    Icon(Icons.menu_book_rounded, color: AppColors.brown),
                label: 'Library',
              ),
              NavigationDestination(
                icon: Icon(Icons.checklist_rounded),
                selectedIcon:
                    Icon(Icons.checklist_rounded, color: AppColors.brown),
                label: 'Notes',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
