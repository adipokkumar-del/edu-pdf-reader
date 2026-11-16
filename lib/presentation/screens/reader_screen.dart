import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../data/services/export_service.dart';
import '../../data/services/reading_store.dart';
import '../../providers/annotation_provider.dart';
import '../../providers/reading_settings.dart';
import '../../providers/study_timer.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/notes_sheet.dart';
import '../widgets/side_panel.dart';
import '../widgets/toolbar_widget.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.path});

  final String path;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  static const _lightText = Color(0xFFEFE6DF);

  final _controller = PdfViewerController();
  final _searchField = TextEditingController();
  final _page = ValueNotifier<int>(1);
  final _pageCount = ValueNotifier<int>(0);

  late final ReadingSettings _settings;
  late final StudyTimer _timer;
  late final PdfTextSearcher _searcher;
  late final List<PdfViewerPagePaintCallback> _paintCallbacks;
  late PdfViewerParams _params;

  Timer? _saveTimer;
  Timer? _searchTimer;

  ReadingStore? _store;
  AnnotationProvider? _annotations;
  ReadingPosition? _saved;
  Set<int> _bookmarks = {};
  bool _canSave = false;
  bool _searching = false;
  bool _panelOpen = false;

  String get _title => p.basenameWithoutExtension(widget.path);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _settings = context.read<ReadingSettings>();
    _timer = context.read<StudyTimer>();

    _searcher = PdfTextSearcher(_controller)..addListener(_onSearchChanged);
    _controller.addListener(_scheduleSave);

    _paintCallbacks = [
      _settings.paintGrain,
      _searcher.pageTextMatchPaintCallback,
    ];
    _params = _buildParams();
    _settings.addListener(_onSettings);
    _timer.onPhaseFinished = _onTimerDone;

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
    _settings.removeListener(_onSettings);
    if (_timer.onPhaseFinished == _onTimerDone) {
      _timer.onPhaseFinished = null;
    }
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

  // ---- Viewer params ------------------------------------------------------

  PdfViewerParams _buildParams() => PdfViewerParams(
        backgroundColor: _settings.viewerBackground,
        margin: 8,
        pageImageColorFilter: _settings.pageFilter,
        textSelectionParams: const PdfTextSelectionParams(enabled: true),
        matchTextColor: const Color(0x66F9A825),
        activeMatchTextColor: const Color(0x99EF6C00),
        pagePaintCallbacks: _paintCallbacks,
        pageOverlaysBuilder: _buildOverlays,
        calculateInitialPageNumber: _initialPage,
        onViewerReady: _onViewerReady,
        onPageChanged: _onPageChanged,
      );

  List<Widget> _buildOverlays(
          BuildContext context, Rect pageRect, PdfPage page) =>
      [PageStrokesLayer(pageIndex: page.pageNumber - 1)];

  int? _initialPage(PdfDocument document, PdfViewerController controller) =>
      _saved?.page;

  void _onSettings() {
    if (!mounted) return;
    setState(() => _params = _buildParams());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.isReady) _controller.invalidate();
    });
  }

  void _onTimerDone(TimerPhase next) {
    if (!mounted) return;
    _snack(next == TimerPhase.rest
        ? 'Focus session complete. Take a ${StudyTimer.restMinutes} minute break.'
        : 'Break is over. Ready for the next session?');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  // ---- Notes & export -----------------------------------------------------

  void _openNotes() {
    final store = _store;
    if (store == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => NotesSheet(
        store: store,
        currentPage: () => _page.value,
      ),
    );
  }

  Future<void> _exportPdf() async {
    final annotations = _annotations;
    if (annotations == null || !_controller.isReady) return;

    final strokes = annotations.allStrokes;
    if (strokes.isEmpty) {
      _snack('Nothing drawn yet, so there is nothing to export.');
      return;
    }

    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Preparing PDF…'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, __) =>
                LinearProgressIndicator(value: v == 0 ? null : v),
          ),
        ),
      ),
    );

    File? file;
    try {
      file = await ExportService.annotatedPdf(
        document: _controller.document,
        strokes: strokes,
        title: _title,
        onProgress: (v) => progress.value = v,
      );
    } catch (_) {
      file = null;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (file == null) {
      _snack('Could not create the PDF. Please try again.');
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: '$_title (annotated)',
    );
  }

  Future<void> _exportNotes() async {
    final store = _store;
    if (store == null) return;

    final notes = store.loadNotes();
    final bookmarks = _bookmarks.toList()..sort();
    if (notes.trim().isEmpty && bookmarks.isEmpty) {
      _snack('No notes or bookmarks to export yet.');
      return;
    }

    final file = await ExportService.notesFile(
      title: _title,
      notes: notes,
      bookmarks: bookmarks,
    );
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/plain')],
      subject: '$_title (notes)',
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
      case 'notes':
        _openNotes();
      case 'goto':
        _goTo();
      case 'share':
        _share();
    }
  }

  // ---- UI -----------------------------------------------------------------

  ThemeData _darkChrome(ThemeData base) => base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0C0A),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: const Color(0xFF1B1411),
          foregroundColor: _lightText,
          iconTheme: const IconThemeData(color: _lightText),
          actionsIconTheme: const IconThemeData(color: _lightText),
          titleTextStyle: const TextStyle(
            color: _lightText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

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
        final dark = _settings.mode == ReadingMode.dark;
        final base = Theme.of(context);
        final panelWidth =
            math.min(300.0, MediaQuery.sizeOf(context).width * 0.84);

        void closePanelThen(VoidCallback action) {
          setState(() => _panelOpen = false);
          action();
        }

        return Theme(
          data: dark ? _darkChrome(base) : base,
          child: PopScope(
            canPop: !drawing && !_searching && !_panelOpen,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_panelOpen) {
                setState(() => _panelOpen = false);
              } else if (_searching) {
                _closeSearch();
              } else {
                annotations.setDrawing(false);
              }
            },
            child: Scaffold(
              appBar: _searching
                  ? _buildSearchBar(dark)
                  : _buildBar(drawing, dark),
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
                    top: 8,
                    left: 8,
                    child: TimerPill(
                      onTap: () => setState(() => _panelOpen = true),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildPagePill()),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    top: 0,
                    bottom: 0,
                    width: 26,
                    right: _panelOpen ? panelWidth : 0,
                    child: Center(child: _buildHandle()),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    top: 0,
                    bottom: 0,
                    width: panelWidth,
                    right: _panelOpen ? 0 : -panelWidth,
                    child: SidePanel(
                      annotating: drawing,
                      onClose: () => setState(() => _panelOpen = false),
                      onSearch: () => setState(() {
                        _panelOpen = false;
                        _searching = true;
                      }),
                      onBookmarks: () => closePanelThen(_showBookmarks),
                      onAnnotate: () => closePanelThen(
                        () => annotations.setDrawing(!drawing),
                      ),
                      onNotes: () => closePanelThen(_openNotes),
                      onExportPdf: () => closePanelThen(_exportPdf),
                      onExportNotes: () => closePanelThen(_exportNotes),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: drawing ? const AnnotationToolbar() : null,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildHandle() {
    const radius = BorderRadius.horizontal(left: Radius.circular(12));
    return Material(
      color: AppColors.brown.withValues(alpha: 0.85),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => setState(() => _panelOpen = !_panelOpen),
        child: SizedBox(
          width: 26,
          height: 64,
          child: Icon(
            _panelOpen
                ? Icons.chevron_right_rounded
                : Icons.chevron_left_rounded,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  AppBar _buildBar(bool drawing, bool dark) {
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
                color: marked
                    ? (dark ? AppColors.brownLight : AppColors.brown)
                    : null,
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
            foregroundColor: drawing ? Colors.white : null,
          ),
        ),
        PopupMenuButton<String>(
          color: Colors.white,
          onSelected: _onMenu,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
            PopupMenuItem(value: 'notes', child: Text('Notes')),
            PopupMenuItem(value: 'goto', child: Text('Go to page')),
            PopupMenuItem(value: 'share', child: Text('Share PDF')),
          ],
        ),
      ],
    );
  }

  AppBar _buildSearchBar(bool dark) {
    final textColor = dark ? _lightText : null;
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
        style: TextStyle(color: textColor),
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
            style: TextStyle(
              color: dark ? _lightText : AppColors.textSecondary,
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
