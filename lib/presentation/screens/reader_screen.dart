import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/system_ui.dart';
import '../../data/services/export_service.dart';
import '../../data/services/share_notes.dart';
import '../../data/services/reading_store.dart';
import '../../providers/annotation_provider.dart';
import '../../providers/focus_mode.dart';
import '../../providers/reading_settings.dart';
import '../../providers/recent_provider.dart';
import '../../providers/study_timer.dart';
import '../widgets/double_tap_zoom.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/notes_sheet.dart';
import '../widgets/scroll_indicators.dart';
import '../widgets/scroll_thumb.dart';
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
  static const _baseFriction = 0.0000135;
  static const _handleSize = 44.0;

  final _controller = PdfViewerController();
  final _searchField = TextEditingController();
  final _page = ValueNotifier<int>(1);
  final _pageCount = ValueNotifier<int>(0);

  late final ReadingSettings _settings;
  late final StudyTimer _timer;
  late final FocusMode _focus;
  late final RecentProvider _recent;
  late final PdfTextSearcher _searcher;
  late final List<PdfViewerPagePaintCallback> _paintCallbacks;
  late PdfViewerParams _params;

  // Extra room above the first page so it clears the camera notch/status bar.
  double _topInset = 0;
  double _viewWidth = 0;
  double _bottomInset = 0;
  double _lastViewTop = 0;
  double _scrollAcc = 0;

  Timer? _saveTimer;
  Timer? _searchTimer;

  ReadingStore? _store;
  AnnotationProvider? _annotations;
  ReadingPosition? _saved;
  ReadingPosition? _pending;
  Set<int> _bookmarks = {};
  bool _canSave = false;
  bool _searching = false;
  bool _panelOpen = false;

  // Round panel button being dragged.
  Offset? _dragPos;
  Offset _dragOrigin = Offset.zero;

  String get _title => p.basenameWithoutExtension(widget.path);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _settings = context.read<ReadingSettings>();
    _timer = context.read<StudyTimer>();
    _focus = context.read<FocusMode>();
    _recent = context.read<RecentProvider>();
    _focus.enterReader();

    _searcher = PdfTextSearcher(_controller)..addListener(_onSearchChanged);
    _controller.addListener(_onViewerMoved);

    _paintCallbacks = [
      _settings.paintGrain,
      _searcher.pageTextMatchPaintCallback,
    ];
    _params = _buildParams();
    _settings.addListener(_onSettings);
    _timer.onPhaseFinished = _onTimerDone;
    SystemUi.hidden.addListener(_onUiChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recent.touch(widget.path);
    });

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
    _controller.removeListener(_onViewerMoved);
    _settings.removeListener(_onSettings);
    SystemUi.hidden.removeListener(_onUiChanged);
    if (_timer.onPhaseFinished == _onTimerDone) {
      _timer.onPhaseFinished = null;
    }
    _searcher.removeListener(_onSearchChanged);
    _searcher.dispose();
    _searchField.dispose();
    _page.dispose();
    _pageCount.dispose();
    _annotations?.dispose();
    _focus.leaveReader();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
    }
  }

  void _onUiChanged() {
    if (mounted) setState(() {});
  }

  // ---- Viewer params ------------------------------------------------------

  /// Higher speed = less friction, so a flick travels further.
  double _friction(double speed) =>
      math.pow(_baseFriction, 1 / speed).toDouble();

  PdfViewerParams _buildParams() => PdfViewerParams(
        backgroundColor: _settings.viewerBackground,
        margin: 8,
        // Lets you zoom out far enough to see several pages at once.
        // ignore: deprecated_member_use
        minScale: 0.2,
        // ignore: deprecated_member_use
        useAlternativeFitScaleAsMinScale: false,
        verticalCacheExtent: 2.0,
        onePassRenderingSizeThreshold: 1600,
        pageImageColorFilter: _settings.pageFilter,
        interactionEndFrictionCoefficient: _friction(_settings.scrollSpeed),
        textSelectionParams: const PdfTextSelectionParams(enabled: true),
        matchTextColor: const Color(0x66F9A825),
        activeMatchTextColor: const Color(0x99EF6C00),
        pagePaintCallbacks: _paintCallbacks,
        pageOverlaysBuilder: _buildOverlays,
        calculateInitialPageNumber: _initialPage,
        layoutPages: _layoutPages,
        onViewerReady: _onViewerReady,
        onPageChanged: _onPageChanged,
      );

  /// Vertical layout like the default, with two differences:
  /// - page 1 starts right below the top ribbon (status bar + toolbar);
  /// - a little extra side room, so the PDF opens slightly zoomed out
  ///   instead of exactly fitting the screen width.
  PdfPageLayout _layoutPages(List<PdfPage> pages, PdfViewerParams params) {
    final margin = params.margin;
    final maxW = pages.fold<double>(0, (w, p) => math.max(w, p.width));
    final width = maxW * 1.08 + margin * 2;
    // Screen distances must be converted to document units (zoom ~ view/width).
    final toDoc = _viewWidth > 0 ? width / _viewWidth : 1.0;
    final ribbon = _topInset + kToolbarHeight + 6;
    final layouts = <Rect>[];
    var y = ribbon * toDoc;
    for (final page in pages) {
      layouts.add(Rect.fromLTWH((width - page.width) / 2, y, page.width, page.height));
      y += page.height + margin;
    }
    // Room under the last page so it can scroll fully above the navigation bar.
    y += (_bottomInset + 36) * toDoc;
    return PdfPageLayout(pageLayouts: layouts, documentSize: Size(width, y));
  }

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

  /// Where the top of the screen is right now, relative to its page.
  ReadingPosition? _capture() {
    if (!_controller.isReady) return null;
    try {
      final rects = _controller.layout.pageLayouts;
      if (rects.isEmpty) return null;
      final view = _controller.visibleRect;

      // First page whose bottom edge is below the top of the screen.
      var lo = 0;
      var hi = rects.length - 1;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (rects[mid].bottom > view.top) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      final r = rects[lo];
      return ReadingPosition(
        page: lo + 1,
        fx: (view.left - r.left) / r.width,
        fy: (view.top - r.top) / r.height,
        zoom: _controller.currentZoom,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _onViewerReady(
    PdfDocument document,
    PdfViewerController controller,
  ) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pageCount.value = controller.pageCount;
    });

    final saved = _saved;
    if (saved != null) {
      // Pages are measured gradually, so wait, jump, and verify a few times.
      for (var attempt = 0; attempt < 3; attempt++) {
        await Future<void>.delayed(
          Duration(milliseconds: attempt == 0 ? 350 : 300),
        );
        if (!mounted || !controller.isReady) break;
        try {
          final rects = controller.layout.pageLayouts;
          final i = saved.page - 1;
          if (i < 0 || i >= rects.length) break;
          final r = rects[i];
          await controller.goToPosition(
            documentOffset: Offset(
              r.left + saved.fx * r.width,
              r.top + saved.fy * r.height,
            ),
            zoom: saved.zoom > 0 ? saved.zoom : null,
          );
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 150));
        if (_capture()?.page == saved.page) break;
      }
    }
    if (mounted) _canSave = true;
  }

  void _onPageChanged(int? number) {
    if (number == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _page.value = number;
    });
  }

  /// Scrolling down hides the system bars, scrolling up brings them back.
  void _autoHideBars() {
    if (!_controller.isReady) return;
    final top = _controller.visibleRect.top;
    final delta = top - _lastViewTop;
    _lastViewTop = top;
    // Ignore jumps (go to page, restore position) and idle moves.
    if (delta == 0 || delta.abs() > 400) {
      _scrollAcc = 0;
      return;
    }
    if (_searching || _panelOpen || (_annotations?.drawing ?? false)) return;
    if ((delta > 0) != (_scrollAcc > 0)) _scrollAcc = 0;
    _scrollAcc += delta;
    if (_scrollAcc > 60) {
      SystemUi.set(true);
      _scrollAcc = 0;
    } else if (_scrollAcc < -60) {
      SystemUi.set(false);
      _scrollAcc = 0;
    }
  }

  void _onViewerMoved() {
    _autoHideBars();
    if (!_canSave) return;
    final position = _capture();
    if (position != null) _pending = position;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _flush);
  }

  void _flush() {
    final position = _pending;
    if (position != null) _store?.savePosition(position);
  }

  void _saveProgress() {
    if (!_canSave) return;
    final position = _capture() ?? _pending;
    if (position != null) _store?.savePosition(position);
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

  // ---- Notes, text & export -----------------------------------------------

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

  void _appendToNotes(String text) {
    final store = _store;
    if (store == null) return;
    final old = store.loadNotes();
    store.saveNotes(old.isEmpty ? text : '$old\n\n$text');
    _snack('Added to notes');
  }

  /// Copies the whole text of the current page to the clipboard.
  Future<void> _extractText() async {
    if (!_controller.isReady) return;
    final n = _page.value;
    var text = '';
    try {
      final page = _controller.document.pages[n - 1];
      final dynamic loaded = await page.loadText();
      text = ((loaded?.fullText as String?) ?? '').trim();
    } catch (_) {}

    if (!mounted) return;
    if (text.isEmpty) {
      _snack('No selectable text on page $n. It may be a scanned image.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Page $n text copied (${text.length} characters)'),
          action: SnackBarAction(
            label: 'Add to notes',
            onPressed: () => _appendToNotes('[p. $n]\n$text'),
          ),
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
    final s = _store;
    if (s == null) return;
    await shareDocumentNotes(
      context,
      title: _title,
      notes: s.loadNotes(),
      bookmarks: _bookmarks.toList()..sort(),
    );
  }

  // Old text-only version. Unused now; you can delete this whole function.
  // ignore: unused_element
  Future<void> _exportNotesLegacy() async {
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

  /// Quick zoom presets: fit the width, fit the whole page, or zoom out
  /// to see several pages at once.
  Future<void> _setView(String mode) async {
    if (!_controller.isReady) return;
    final page = _page.value;
    try {
      switch (mode) {
        case 'width':
          {
            final matrix = _controller.calcMatrixFitWidthForPage(pageNumber: page);
            if (matrix != null) await _controller.goTo(matrix);
          }
        case 'page':
          {
            final matrix = _controller.calcMatrixForFit(pageNumber: page);
            if (matrix != null) await _controller.goTo(matrix);
          }
        case 'overview':
          {
            final fit = _controller.alternativeFitScale ?? _controller.currentZoom;
            final target = math.max(fit * 0.45, _controller.minScale);
            final view = _controller.viewSize;
            await _controller.zoomOnLocalPosition(
              localPosition: Offset(view.width / 2, view.height / 2),
              newZoom: target,
            );
          }
      }
    } catch (_) {}
  }

  Future<void> _goTo() async {
    SystemUi.set(false);
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
      case 'extract':
        _extractText();
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
        final barsHidden = SystemUi.hidden.value;
        final barVisible = !barsHidden || _searching || drawing;
        final base = Theme.of(context);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUi.style(lightIcons: dark),
          child: Theme(
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
                body: LayoutBuilder(
                  builder: (context, c) => _buildStack(
                    context,
                    c,
                    annotations: annotations,
                    drawing: drawing,
                    hand: hand,
                    dark: dark,
                    barVisible: barVisible,
                  ),
                ),
                bottomNavigationBar:
                    drawing ? const AnnotationToolbar() : null,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStack(
    BuildContext context,
    BoxConstraints c, {
    required AnnotationProvider annotations,
    required bool drawing,
    required bool hand,
    required bool dark,
    required bool barVisible,
  }) {
    final padding = MediaQuery.paddingOf(context);
    _topInset = math.max(_topInset, padding.top);
    _viewWidth = MediaQuery.sizeOf(context).width;
    _bottomInset = math.max(_bottomInset, padding.bottom);
    final barHeight = kToolbarHeight + padding.top;

    // Round panel button: free position, stored as fractions.
    final maxX = math.max(0.0, c.maxWidth - _handleSize);
    final maxY = math.max(0.0, c.maxHeight - _handleSize);
    final home = Offset(_settings.handleFx * maxX, _settings.handleFy * maxY);
    final handlePos = _dragPos ?? home;
    final onLeft = handlePos.dx + _handleSize / 2 < c.maxWidth / 2;
    final panelWidth = math.min(300.0, c.maxWidth * 0.84);

    void closePanelThen(VoidCallback action) {
      setState(() => _panelOpen = false);
      action();
    }

    return Stack(
      children: [
        Positioned.fill(
          child: PdfViewer.file(
            widget.path,
            key: ValueKey(widget.path),
            controller: _controller,
            params: _params,
          ),
        ),
        Positioned.fill(
          child: ScrollIndicators(
            controller: _controller,
            dark: dark,
            inset: EdgeInsets.only(
              top: barVisible ? barHeight : padding.top,
              bottom: padding.bottom + 12,
            ),
          ),
        ),
        if (drawing && !hand)
          Positioned.fill(
            child: InkInputLayer(controller: _controller),
          ),
        if (!drawing)
          Positioned.fill(
            child: DoubleTapDragZoom(
              controller: _controller,
              onSingleTap: SystemUi.toggle,
            ),
          ),
        if (!drawing)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: barVisible ? barHeight : padding.top,
                bottom: padding.bottom + 12,
              ),
              child: AutoHideScrollThumb(controller: _controller, dark: dark),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          top: (barVisible ? barHeight : padding.top) + 8,
          left: 8,
          child: TimerPill(
            onTap: () => setState(() => _panelOpen = true),
          ),
        ),
        Positioned(
          bottom: 16 + padding.bottom,
          left: 0,
          right: 0,
          child: Center(child: _buildPagePill()),
        ),

        // Top bar floats over the page, so hiding it never moves the text.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !barVisible,
            child: AnimatedSlide(
              offset: barVisible ? Offset.zero : const Offset(0, -1.3),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: _searching
                  ? _buildSearchBar(dark)
                  : _buildBar(annotations, drawing, dark),
            ),
          ),
        ),

        if (_panelOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _panelOpen = false),
              child: const ColoredBox(color: Color(0x22000000)),
            ),
          ),
        AnimatedPositioned(
          key: ValueKey('panel-$onLeft'),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          width: panelWidth,
          left: onLeft ? (_panelOpen ? 0 : -panelWidth) : null,
          right: onLeft ? null : (_panelOpen ? 0 : -panelWidth),
          child: SidePanel(
            annotating: drawing,
            onClose: () => setState(() => _panelOpen = false),
            onSearch: () {
              SystemUi.set(false);
              setState(() {
                _panelOpen = false;
                _searching = true;
              });
            },
            onBookmarks: () => closePanelThen(_showBookmarks),
            onAnnotate: () => closePanelThen(
              () => annotations.setDrawing(!drawing),
            ),
            onNotes: () => closePanelThen(_openNotes),
            onExportPdf: () => closePanelThen(_exportPdf),
            onExportNotes: () => closePanelThen(_exportNotes),
            onExtractText: () => closePanelThen(_extractText),
            onViewMode: (mode) => closePanelThen(() => _setView(mode)),
          ),
        ),

        if (!_panelOpen && !drawing)
          Positioned(
            left: handlePos.dx,
            top: handlePos.dy,
            child: _buildHandle(handlePos, maxX, maxY),
          ),
      ],
    );
  }

  Widget _buildHandle(Offset pos, double maxX, double maxY) {
    final dragging = _dragPos != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _panelOpen = true),
      onLongPressStart: (_) {
        HapticFeedback.mediumImpact();
        setState(() {
          _dragOrigin = pos;
          _dragPos = pos;
        });
      },
      onLongPressMoveUpdate: (d) {
        setState(() {
          _dragPos = Offset(
            (_dragOrigin.dx + d.offsetFromOrigin.dx).clamp(0.0, maxX).toDouble(),
            (_dragOrigin.dy + d.offsetFromOrigin.dy).clamp(0.0, maxY).toDouble(),
          );
        });
      },
      onLongPressEnd: (_) {
        final end = _dragPos;
        if (end != null && maxX > 0 && maxY > 0) {
          _settings.setHandle(end.dx / maxX, end.dy / maxY);
        }
        setState(() => _dragPos = null);
      },
      child: AnimatedScale(
        scale: dragging ? 1.18 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: _handleSize,
          height: _handleSize,
          decoration: BoxDecoration(
            color: AppColors.brown.withValues(alpha: dragging ? 0.95 : 0.6),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dragging ? 0.3 : 0.15),
                blurRadius: dragging ? 14 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.tune_rounded, color: Colors.white),
        ),
      ),
    );
  }

  AppBar _buildBar(AnnotationProvider annotations, bool drawing, bool dark) {
    final background = dark ? const Color(0xFF1B1411) : AppColors.background;
    return AppBar(
      titleSpacing: 0,
      backgroundColor: background.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      title: _titleText(),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search_rounded),
          onPressed: () {
            SystemUi.set(false);
            setState(() => _searching = true);
          },
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
            PopupMenuItem(value: 'extract', child: Text('Extract page text')),
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
    final background = dark ? const Color(0xFF1B1411) : AppColors.background;
    final textColor = dark ? _lightText : null;
    return AppBar(
      titleSpacing: 0,
      backgroundColor: background.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
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
