import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/library_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/pdf_file_tile.dart';
import '../widgets/recent_strip.dart';
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
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
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          IconButton(
            tooltip: 'Rescan storage',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<LibraryProvider>().loadLibrary(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Consumer<LibraryProvider>(
          builder: (context, library, _) {
            return switch (library.status) {
              LibraryStatus.loading => const Center(
                  child: CircularProgressIndicator(),
                ),
              LibraryStatus.needsPermission => EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'Allow file access',
                  message:
                      'EduPDF needs access to your storage to find the PDF files on your device.',
                  actionLabel: 'Grant access',
                  onAction: library.requestPermissionAndLoad,
                ),
              LibraryStatus.error => EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Something went wrong',
                  message: 'We could not scan your storage. Please try again.',
                  actionLabel: 'Try again',
                  onAction: library.loadLibrary,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: _buildSearchField(library),
        ),
        const RecentStrip(),
        _buildSortBar(library),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            '$count document${count == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.brown,
            onRefresh: () => library.loadLibrary(silent: true),
            child: docs.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 60),
                      EmptyState(
                        icon: Icons.menu_book_rounded,
                        title: 'No PDFs found',
                        message:
                            'Pull down to rescan, or try a different search.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
        ),
      ],
    );
  }

  Widget _buildSearchField(LibraryProvider library) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color),
        );

    return TextField(
      controller: _searchController,
      onChanged: (value) {
        library.setQuery(value);
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search PDFs',
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon:
            const Icon(Icons.search_rounded, color: AppColors.textSecondary),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary),
                onPressed: () {
                  _searchController.clear();
                  library.setQuery('');
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: border(AppColors.divider),
        enabledBorder: border(AppColors.divider),
        focusedBorder: border(AppColors.brown),
      ),
    );
  }

  Widget _buildSortBar(LibraryProvider library) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final option in SortOption.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildSortChip(library, option),
            ),
        ],
      ),
    );
  }

  Widget _buildSortChip(LibraryProvider library, SortOption option) {
    final selected = library.sort == option;
    return ChoiceChip(
      showCheckmark: false,
      avatar: selected
          ? Icon(
              library.ascending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 16,
              color: Colors.white,
            )
          : null,
      label: Text(option.label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.brownDark,
        fontWeight: FontWeight.w700,
      ),
      selected: selected,
      selectedColor: AppColors.brown,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppColors.brown : AppColors.brownLight),
      shape: const StadiumBorder(),
      onSelected: (_) => library.setSort(option),
    );
  }
}
