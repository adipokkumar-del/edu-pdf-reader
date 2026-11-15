import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../data/services/reading_store.dart';
import '../../providers/annotation_provider.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/toolbar_widget.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.path});

  final String path;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  final _controller = PdfViewerController();
  final _searchField = TextEditingController();
  final _page = ValueNotifier<int>(1);
  final _pageCount = ValueNotifier<int>(0);
  late final PdfTextSearcher _searcher;
  late final PdfViewerParams _params;

  Timer? _saveTimer;
  Timer? _searchTimer;

  ReadingStore? _store;
  AnnotationProvider? _annotations;
  ReadingPosition? _saved;
  Set<int> _bookmarks = {};
  bool _canSave = false;
  bool _searching = false;

  String get _title => p.basenameWithoutExtension(widget.path);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _searcher = PdfTextSearcher(_controller)..addListener(_onSearchChanged);
    _controller.addListener(_scheduleSave);

    _params = PdfViewerParams(
      backgroundColor: AppColors.brownSurface,
      margin: 8,
      textSelectionParams: const PdfTextSelectionParams(enabled: true),
      matchTextColor: const Color(0x66F9A825),
      activeMatchTextColor: const Color(0x99EF6C00),
      pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
      pageOverlaysBuilder: (context, pageRect, page) => [
        PageStrokesLayer(pageIndex: page.pageNumber - 1),
      ],
      calculateInitialPageNumber: (document, controller) => _saved?.page,
      onViewerReady: _onViewerReady,
      onPageChanged: _onPageChanged,
    );

    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final store = ReadingStore(prefs, widget.path);
    if (!mounted) return;
    setState(() {
      _store = store;
      _saved = store.loadPosition();
      _bookmarks = store.loadBookmarks().toSet();
      _annotations = AnnotationProvider(prefs, widget.path);
      _page.value = _saved?.page ?? 1;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _searchTimer?.cancel();
    _saveProgress();
    _controller.removeListener(_scheduleSave);
    _searcher.removeListener(_onSearchChanged);
    _searcher.dispose();
    _searchField.dispose();
    _page.dispose();
    _pageCount.dispose();
    _annotations?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
    }
  }

  // ---- Auto-resume --------------------------------------------------------

  Future<void> _onViewerReady(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    final saved = _saved;
    if (saved != null && saved.zoom > 0) {
      try {
        await controller.goToPosition(
          documentOffset: Offset(saved.x, saved.y),
          zoom: saved.zoom,
        );
      } catch (_) {}
    }
    _canSave = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageCount.value = controller.pageCount;
    });
  }

  void _onPageChanged(int? number) {
    if (number == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _page.value = number;
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveProgress);
  }

  void _saveProgress() {
    final store = _store;
    if (store == null || !_canSave || !_controller.isReady) return;
    try {
      final top = _controller.visibleRect.topLeft;
      store.savePosition(ReadingPosition(
        page: _controller.pageNumber ?? _page.value,
        x: top.dx,
        y: top.dy,
        zoom: _controller.currentZoom,
      ));
    } catch (_) {}
  }

  // ---- Search -------------------------------------------------------------

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchTyped(String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 400), () {
      final q = query.trim();
      if (q.isEmpty) {
        _searcher.resetTextSearch();
      } else {
        _searcher.startTextSearch(q, caseInsensitive: true);
      }
    });
  }

  void _closeSearch() {
    _searchTimer?.cancel();
    _searcher.resetTextSearch();
    _searchField.clear();
    setState(() => _searching = false);
  }

  String get _searchStatus {
    if (_searchField.text.trim().isEmpty) return '';
    if (!_searcher.hasMatches) return _searcher.isSearching ? '…' : '0';
    final current = (_searcher.currentIndex ?? 0) + 1;
    final more = _searcher.isSearching ? '+' : '';
    return '$current/${_searcher.matches.length}$more';
  }

  // ---- Bookmarks ----------------------------------------------------------

  void _toggleBookmark(int page) {
    setState(() {
      if (!_bookmarks.remove(page)) _bookmarks.add(page);
    });
    _store?.saveBookmarks(_bookmarks);
  }

  void _showBookmarks() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final pages = _bookmarks.toList()..sort();
          if (pages.isEmpty) {
            return const SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  'No bookmarks yet',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              for (final n in pages)
                ListTile(
                  leading: const Icon(Icons.bookmark_rounded,
                      color: AppColors.brown),
                  title: Text('Page $n'),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      setState(() {
                        _bookmarks.remove(n);
                      });
                      _store?.saveBookmarks(_bookmarks);
                      setSheet(() {});
                    },
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _controller.goToPage(pageNumber: n);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  // ---- Other actions ------------------------------------------------------

  Future<void> _goTo() async {
    final controller = TextEditingController();
    final total = _pageCount.value;
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Go to page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 – $total'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (value == null || total == 0) return;
    _controller.goToPage(pageNumber: value.clamp(1, total));
  }

  Future<void> _share() =>
      Share.shareXFiles([XFile(widget.path)], subject: _title);

  void _onMenu(String value) {
    switch (value) {
      case 'bookmarks':
        _showBookmarks();
      case 'goto':
        _goTo();
      case 'share':
        _share();
    }
  }

  // ---- UI -----------------------------------------------------------------

  Widget _titleText() => Text(
        _title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 18),
      );

  @override
  Widget build(BuildContext context) {
    final annotations = _annotations;
    if (annotations == null) {
      return Scaffold(
        appBar: AppBar(title: _titleText()),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return ChangeNotifierProvider<AnnotationProvider>.value(
      value: annotations,
      child: Builder(builder: (context) {
        final drawing =
            context.select<AnnotationProvider, bool>((a) => a.drawing);
        final hand = context.select<AnnotationProvider, bool>((a) => a.hand);

        return PopScope(
          canPop: !drawing && !_searching,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_searching) {
              _closeSearch();
            } else {
              annotations.setDrawing(false);
            }
          },
          child: Scaffold(
            appBar: _searching ? _buildSearchBar() : _buildBar(drawing),
            body: Stack(
              children: [
                Positioned.fill(
                  child: PdfViewer.file(
                    widget.path,
                    key: ValueKey(widget.path),
                    controller: _controller,
                    params: _params,
                  ),
                ),
                if (drawing && !hand)
                  Positioned.fill(
                    child: InkInputLayer(controller: _controller),
                  ),
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildPagePill()),
                ),
              ],
            ),
            bottomNavigationBar: drawing ? const AnnotationToolbar() : null,
          ),
        );
      }),
    );
  }

  AppBar _buildBar(bool drawing) {
    final annotations = _annotations!;
    return AppBar(
      titleSpacing: 0,
      title: _titleText(),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => setState(() => _searching = true),
        ),
        ValueListenableBuilder<int>(
          valueListenable: _page,
          builder: (_, page, __) {
            final marked = _bookmarks.contains(page);
            return IconButton(
              tooltip: marked ? 'Remove bookmark' : 'Bookmark this page',
              icon: Icon(
                marked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: marked ? AppColors.brown : null,
              ),
              onPressed: () => _toggleBookmark(page),
            );
          },
        ),
        IconButton(
          tooltip: drawing ? 'Done' : 'Annotate',
          isSelected: drawing,
          icon: const Icon(Icons.draw_outlined),
          selectedIcon: const Icon(Icons.check_rounded),
          onPressed: () => annotations.setDrawing(!drawing),
          style: IconButton.styleFrom(
            backgroundColor: drawing ? AppColors.brown : null,
            foregroundColor: drawing ? Colors.white : AppColors.brownDark,
          ),
        ),
        PopupMenuButton<String>(
          color: Colors.white,
          onSelected: _onMenu,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
            PopupMenuItem(value: 'goto', child: Text('Go to page')),
            PopupMenuItem(value: 'share', child: Text('Share')),
          ],
        ),
      ],
    );
  }

  AppBar _buildSearchBar() {
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _closeSearch,
      ),
      title: TextField(
        controller: _searchField,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: _onSearchTyped,
        decoration: const InputDecoration(
          hintText: 'Search in document',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
      actions: [
        Center(
          child: Text(
            _searchStatus,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Previous match',
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: _searcher.hasMatches ? _searcher.goToPrevMatch : null,
        ),
        IconButton(
          tooltip: 'Next match',
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: _searcher.hasMatches ? _searcher.goToNextMatch : null,
        ),
      ],
    );
  }

  Widget _buildPagePill() {
    return AnimatedBuilder(
      animation: Listenable.merge([_page, _pageCount]),
      builder: (_, __) {
        if (_pageCount.value == 0) return const SizedBox.shrink();
        return Material(
          color: AppColors.brownDark.withValues(alpha: 0.9),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _goTo,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${_page.value} / ${_pageCount.value}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
