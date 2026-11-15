import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/annotation_provider.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/empty_state.dart';
import '../widgets/toolbar_widget.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.path});

  final String path;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _gap = 12.0;
  static const _zoomLevels = [1.0, 1.5, 2.0, 3.0];

  final _scroll = ScrollController();
  final _page = ValueNotifier<int>(0);
  final _cache = <String, Future<Uint8List?>>{};
  Future<void> _tail = Future.value();

  SharedPreferences? _prefs;
  PdfDocument? _doc;
  AnnotationProvider? _annotations;
  List<double> _aspects = const [];
  Object? _error;

  double _zoom = 1.0;
  double _pageW = 0;
  double _viewH = 0;
  bool _restored = false;

  String get _title => p.basenameWithoutExtension(widget.path);
  String get _pageKey => 'last_page:${widget.path}';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _page.dispose();
    _annotations?.dispose();
    _doc?.close();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final doc = await PdfDocument.openFile(widget.path);
      final aspects = <double>[];
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        aspects.add(page.height / page.width);
        await page.close();
      }
      if (aspects.isEmpty) throw StateError('Empty document');
      if (!mounted) {
        await doc.close();
        return;
      }
      setState(() {
        _prefs = prefs;
        _doc = doc;
        _aspects = aspects;
        _annotations = AnnotationProvider(prefs, widget.path);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  // ---- Page geometry ------------------------------------------------------

  double _pageH(int i) => _pageW * _aspects[i];

  double _offsetOf(int index) {
    var offset = 0.0;
    for (var k = 0; k < index; k++) {
      offset += _pageH(k) + _gap;
    }
    return offset;
  }

  int _indexAt(double probe) {
    var top = _gap;
    for (var i = 0; i < _aspects.length; i++) {
      final bottom = top + _pageH(i);
      if (probe < bottom + _gap / 2) return i;
      top = bottom + _gap;
    }
    return _aspects.length - 1;
  }

  void _jumpTo(int index) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo(_offsetOf(index).clamp(0.0, max));
  }

  void _onScroll() {
    if (_aspects.isEmpty || _pageW == 0 || !_scroll.hasClients) return;
    final index = _indexAt(_scroll.offset + _viewH / 2);
    if (index != _page.value) {
      _page.value = index;
      _prefs?.setInt(_pageKey, index);
    }
  }

  // ---- Rendering ----------------------------------------------------------

  /// Runs tasks one at a time so only one PDF page is open at once.
  Future<T> _serial<T>(Future<T> Function() task) {
    final run = _tail.then((_) => task());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<Uint8List?> _render(int index, int px) async {
    final doc = _doc;
    if (doc == null) return null;
    try {
      final page = await doc.getPage(index + 1);
      try {
        final image = await page.render(
          width: px.toDouble(),
          height: px * _aspects[index],
          format: PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 85,
        );
        return image?.bytes;
      } finally {
        await page.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _image(int index, int px) {
    final key = '$index@$px';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final future = _serial(() => _render(index, px));
    _cache[key] = future;
    while (_cache.length > 10) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  // ---- Actions ------------------------------------------------------------

  void _cycleZoom() {
    final page = _page.value;
    final next =
        _zoomLevels[(_zoomLevels.indexOf(_zoom) + 1) % _zoomLevels.length];
    setState(() => _zoom = next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(page));
  }

  Future<void> _goTo() async {
    final controller = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Go to page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 – ${_aspects.length}'),
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
    if (value == null) return;
    _jumpTo((value - 1).clamp(0, _aspects.length - 1));
  }

  Future<void> _share() =>
      Share.shareXFiles([XFile(widget.path)], subject: _title);

  // ---- UI -----------------------------------------------------------------

  Widget _titleText() => Text(
        _title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 18),
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: _titleText()),
        body: const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Cannot open this PDF',
          message: 'The file may be damaged, password-protected or moved.',
        ),
      );
    }

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

        return PopScope(
          canPop: !drawing,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) annotations.setDrawing(false);
          },
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: _titleText(),
              actions: [
                TextButton(
                  onPressed: _cycleZoom,
                  child: Text(
                    _zoom == _zoom.roundToDouble()
                        ? '${_zoom.toInt()}×'
                        : '$_zoom×',
                    style: const TextStyle(
                      color: AppColors.brown,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: drawing ? 'Done' : 'Annotate',
                  isSelected: drawing,
                  icon: const Icon(Icons.draw_outlined),
                  selectedIcon: const Icon(Icons.check_rounded),
                  onPressed: () => annotations.setDrawing(!drawing),
                  style: IconButton.styleFrom(
                    backgroundColor: drawing ? AppColors.brown : null,
                    foregroundColor:
                        drawing ? Colors.white : AppColors.brownDark,
                  ),
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: _share,
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.brownSurface,
                    child: LayoutBuilder(
                      builder: (context, c) => _buildViewer(context, c, drawing),
                    ),
                  ),
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

  Widget _buildPagePill() {
    return ValueListenableBuilder<int>(
      valueListenable: _page,
      builder: (_, value, __) => Material(
        color: AppColors.brownDark.withValues(alpha: 0.9),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _goTo,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '${value + 1} / ${_aspects.length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewer(BuildContext context, BoxConstraints c, bool drawing) {
    _viewH = c.maxHeight;
    _pageW = (c.maxWidth - _gap * 2) * _zoom;

    if (!_restored) {
      _restored = true;
      final saved =
          (_prefs?.getInt(_pageKey) ?? 0).clamp(0, _aspects.length - 1);
      if (saved > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpTo(saved);
          _page.value = saved;
        });
      }
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (_pageW * dpr).round().clamp(240, 2800);
    final physics = drawing
        ? const NeverScrollableScrollPhysics()
        : const ClampingScrollPhysics();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: physics,
      child: SizedBox(
        width: _pageW + _gap * 2,
        height: c.maxHeight,
        child: ListView.builder(
          controller: _scroll,
          physics: physics,
          cacheExtent: c.maxHeight,
          padding: const EdgeInsets.all(_gap),
          itemCount: _aspects.length,
          itemBuilder: (context, i) => Padding(
            padding: EdgeInsets.only(
              bottom: i == _aspects.length - 1 ? 0 : _gap,
            ),
            child: _PageTile(
              key: ValueKey('page-$i'),
              index: i,
              width: _pageW,
              height: _pageH(i),
              image: _image(i, px),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    super.key,
    required this.index,
    required this.width,
    required this.height,
    required this.image,
  });

  final int index;
  final double width;
  final double height;
  final Future<Uint8List?> image;

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AnnotationProvider>();

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: AppColors.brownDark.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: image,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes != null) {
                return Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true);
              }
              if (snapshot.connectionState == ConnectionState.done) {
                return const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: AppColors.textSecondary),
                );
              }
              return const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          ),
          DrawingCanvas(
            strokes: a.strokesFor(index),
            enabled: a.drawing,
            tool: a.tool,
            color: a.color,
            onStroke: (stroke) => a.addStroke(index, stroke),
            onErase: (at, aspect) => a.eraseAt(index, at, aspect),
            onEraseEnd: a.endErase,
          ),
        ],
      ),
    );
  }
}
