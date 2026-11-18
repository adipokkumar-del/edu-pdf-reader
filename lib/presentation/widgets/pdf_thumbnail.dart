import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/thumbnail_service.dart';

class PdfThumbnail extends StatefulWidget {
  const PdfThumbnail({
    super.key,
    required this.path,
    required this.sizeBytes,
    required this.modified,
    this.width = 54,
    this.height = 72,
  });

  final String path;
  final int sizeBytes;
  final DateTime modified;
  final double width;
  final double height;

  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  ThumbnailHandle? _handle;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(PdfThumbnail old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.sizeBytes != widget.sizeBytes ||
        old.modified != widget.modified) {
      _handle?.cancel();
      _bytes = null;
      _start();
    }
  }

  void _start() {
    final handle = ThumbnailService.instance
        .request(widget.path, widget.sizeBytes, widget.modified);
    _handle = handle;
    handle.future.then((bytes) {
      if (mounted && _handle == handle && bytes != null) {
        setState(() => _bytes = bytes);
      }
    });
  }

  @override
  void dispose() {
    _handle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.brownSurface,
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(8),
        ),
        child: bytes == null
            ? const Center(
                child: Icon(Icons.picture_as_pdf_rounded,
                    size: 20, color: AppColors.brownLight),
              )
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: (widget.width * 3).round(),
              ),
      ),
    );
  }
}
