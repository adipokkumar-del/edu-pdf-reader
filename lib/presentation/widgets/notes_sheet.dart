import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_colors.dart';
import '../../data/services/reading_store.dart';

/// Per-document notepad. Plain text, so pasted text keeps its line breaks.
class NotesSheet extends StatefulWidget {
  const NotesSheet({
    super.key,
    required this.store,
    required this.currentPage,
  });

  final ReadingStore store;
  final int Function() currentPage;

  @override
  State<NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<NotesSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.store.loadNotes());
  Timer? _timer;

  void _scheduleSave() {
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 500),
      () => widget.store.saveNotes(_text.text),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.store.saveNotes(_text.text);
    _text.dispose();
    super.dispose();
  }

  void _insert(String value) {
    final current = _text.value;
    final sel = current.selection;
    final start = sel.isValid ? sel.start : current.text.length;
    final end = sel.isValid ? sel.end : start;
    _text.value = TextEditingValue(
      text: current.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _scheduleSave();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text;
    if (value == null || value.isEmpty) return;
    _insert(value);
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notes copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Notes',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('Paste'),
                  ),
                  IconButton(
                    tooltip: 'Insert page reference',
                    icon: const Icon(Icons.pin_drop_outlined),
                    onPressed: () => _insert('[p. ${widget.currentPage()}] '),
                  ),
                  IconButton(
                    tooltip: 'Copy all',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: _copyAll,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  onChanged: (_) => _scheduleSave(),
                  decoration: InputDecoration(
                    hintText: 'Write or paste notes for this document…',
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.brown),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
