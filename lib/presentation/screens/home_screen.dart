import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/library_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/pdf_file_tile.dart';
import '../widgets/recent_strip.dart';
import '../widgets/library_menu.dart';
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Re-check access when the user returns from the system settings page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final library = context.read<LibraryProvider>();
    if (library.status == LibraryStatus.needsPermission) {
      library.loadLibrary();
    }
  }

  void _openReader(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(path: path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF6ECE5), AppColors.background],
            stops: [0, 0.35],
          ),
        ),
        child: Consumer<LibraryProvider>(
          builder: (context, library, _) {
            return switch (library.status) {
              LibraryStatus.loading => const SafeArea(
                  child: Center(child: CircularProgressIndicator()),
                ),
              LibraryStatus.needsPermission => SafeArea(
                  child: EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'Allow file access',
                    message:
                        'EduPDF needs access to your storage to find the PDF files on your device.',
                    actionLabel: 'Grant access',
                    onAction: library.requestPermissionAndLoad,
                  ),
                ),
              LibraryStatus.error => SafeArea(
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Something went wrong',
                    message: 'We could not scan your storage. Please try again.',
                    actionLabel: 'Try again',
                    onAction: library.loadLibrary,
                  ),
                ),
              LibraryStatus.ready => _buildLibrary(library),
            };
          },
        ),
      ),
    );
  }

  Widget _buildLibrary(LibraryProvider library) {
    final docs = library.documents;
    final count = docs.length;

    return RefreshIndicator(
      color: AppColors.brown,
      edgeOffset: MediaQuery.paddingOf(context).top,
      onRefresh: () => library.loadLibrary(silent: true),
      child: Scrollbar(
        controller: _scroll,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              toolbarHeight: 52,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: AppColors.background.withValues(alpha: 0.96),
              titleSpacing: 20,
              titleTextStyle: GoogleFonts.lora(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.brownDark,
              ),
              title: const Row(
                children: [
                  Icon(Icons.local_library_rounded,
                      size: 22, color: AppColors.brown),
                  SizedBox(width: 8),
                  Text('My Library'),
                ],
              ),
              actions: [
                const LibraryMenu(),
                IconButton(
                  tooltip: 'Rescan storage',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => library.loadLibrary(),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _buildSearchRow(library),
              ),
            ),
            const SliverToBoxAdapter(child: RecentStrip()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Text(
                  '$count document${count == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (docs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.menu_book_rounded,
                  title: 'No PDFs found',
                  message: 'Pull down to rescan, or try a different search.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return PdfFileTile(
                      document: doc,
                      onTap: () => _openReader(doc.path),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow(LibraryProvider library) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color),
        );

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                library.setQuery(value);
                setState(() {});
              },
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search PDFs',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded,
                    size: 18, color: AppColors.textSecondary),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 38, minHeight: 38),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.textSecondary),
                        onPressed: () {
                          _searchController.clear();
                          library.setQuery('');
                          setState(() {});
                        },
                      ),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: border(AppColors.divider),
                enabledBorder: border(AppColors.divider),
                focusedBorder: border(AppColors.brown),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SortButton(library: library),
      ],
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.library});

  final LibraryProvider library;

  @override
  Widget build(BuildContext context) {
    final arrow = library.ascending
        ? Icons.arrow_upward_rounded
        : Icons.arrow_downward_rounded;

    return PopupMenuButton<SortOption>(
      tooltip: 'Sort',
      color: Colors.white,
      position: PopupMenuPosition.under,
      onSelected: library.setSort,
      itemBuilder: (_) => [
        for (final option in SortOption.values)
          PopupMenuItem<SortOption>(
            value: option,
            height: 40,
            child: Row(
              children: [
                Expanded(child: Text(option.label)),
                if (library.sort == option)
                  Icon(arrow, size: 16, color: AppColors.brown),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert_rounded,
                size: 18, color: AppColors.brown),
            const SizedBox(width: 4),
            Text(
              library.sort.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brownDark,
              ),
            ),
            const SizedBox(width: 2),
            Icon(arrow, size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
