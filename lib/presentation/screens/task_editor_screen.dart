import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/native_bridge.dart';
import '../../data/models/task_model.dart';
import '../../providers/tasks_provider.dart';
import '../../data/models/annotation_model.dart';
import 'sketch_screen.dart';

class _Row {
  _Row(String text, this.done)
      : controller = TextEditingController(text: text),
        focus = FocusNode();

  final TextEditingController controller;
  final FocusNode focus;
  bool done;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({super.key, this.task});

  final TaskModel? task;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  final List<_Row> _rows = [];

  bool _remind = false;
  bool _alarm = false;
  bool _daily = false;
  DateTime? _when;
  List<Stroke> _sketch = [];
  bool _exactOk = true;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _body = TextEditingController(text: t?.body ?? '');
    if (t != null) {
      for (final i in t.items) {
        _rows.add(_Row(i.text, i.done));
      }
      _when = t.remindAt;
      _remind = t.remindAt != null;
      _alarm = t.alarm;
      _daily = t.repeatDaily;
      _sketch = List.of(t.sketch);
    }
    _checkExact();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _checkExact() {
    NativeBridge.canExactAlarms().then((ok) {
      if (mounted) setState(() => _exactOk = ok);
    });
  }

  void _addRow() {
    final row = _Row('', false);
    setState(() => _rows.add(row));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.focus.requestFocus();
    });
  }

  void _removeRow(_Row row) {
    setState(() => _rows.remove(row));
    row.dispose();
  }

  void _setRemind(bool value) {
    setState(() {
      _remind = value;
      if (value && _when == null) {
        final n = DateTime.now().add(const Duration(hours: 1));
        _when = DateTime(n.year, n.month, n.day, n.hour, n.minute);
      }
    });
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final initial = _when ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
    _checkExact();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final items = [
      for (final r in _rows)
        if (r.controller.text.trim().isNotEmpty)
          CheckItem(text: r.controller.text.trim(), done: r.done),
    ];
    final title = _title.text.trim();
    final body = _body.text.trim();

    if (title.isEmpty && body.isEmpty && items.isEmpty && _sketch.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final when = _remind ? _when : null;
    if (when != null && !_daily && when.isBefore(DateTime.now())) {
      _snack('Please pick a time in the future.');
      return;
    }

    if (when != null) {
      final status = await Permission.notification.request();
      if (!mounted) return;
      if (!status.isGranted) {
        _snack('Notifications are blocked, so the reminder may not show.');
      }
    }

    final model = widget.task ?? TaskModel(id: TaskModel.newId());
    model
      ..title = title
      ..body = body
      ..items = items
      ..sketch = _sketch
      ..remindAt = when
      ..alarm = _alarm
      ..repeatDaily = _daily && when != null;

    if (!mounted) return;
    context.read<TasksProvider>().upsert(model);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.task == null ? 'New note' : 'Edit note'),
          actions: [
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.check_rounded),
              onPressed: _save,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
            ),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'Write a note…',
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 28),
            _heading('Checklist'),
            for (final row in _rows)
              Row(
                children: [
                  Checkbox(
                    value: row.done,
                    onChanged: (v) => setState(() => row.done = v ?? false),
                  ),
                  Expanded(
                    child: TextField(
                      controller: row.controller,
                      focusNode: row.focus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _addRow(),
                      style: TextStyle(
                        decoration:
                            row.done ? TextDecoration.lineThrough : null,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Item',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => _removeRow(row),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item'),
              ),
            ),
            const Divider(height: 28),
            _heading('Drawing'),
            _sketchTile(),
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Remind me',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              value: _remind,
              onChanged: _setRemind,
            ),
            if (_remind) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded, color: AppColors.brown),
                title: Text(
                  _when == null
                      ? 'Pick date and time'
                      : formatWhen(_when!, daily: false),
                ),
                subtitle: _when == null
                    ? null
                    : Text(
                        '${_when!.day}/${_when!.month}/${_when!.year}',
                      ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickWhen,
              ),
              const SizedBox(height: 4),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.notifications_outlined),
                    label: Text('Notification'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.alarm_rounded),
                    label: Text('Alarm'),
                  ),
                ],
                selected: {_alarm},
                onSelectionChanged: (s) => setState(() => _alarm = s.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeat daily'),
                value: _daily,
                onChanged: (v) => setState(() => _daily = v),
              ),
              if (!_exactOk)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brownSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'For exact timing, allow "Alarms & reminders" for this app.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: NativeBridge.openExactAlarmSettings,
                        child: const Text('Allow'),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editSketch() async {
    final result = await Navigator.of(context).push<List<Stroke>>(
      MaterialPageRoute(builder: (_) => SketchScreen(initial: _sketch)),
    );
    if (result != null && mounted) setState(() => _sketch = result);
  }

  Widget _sketchTile() {
    if (_sketch.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _editSketch,
          icon: const Icon(Icons.brush_rounded),
          label: const Text('Add drawing'),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: _editSketch,
          child: SketchPreview(strokes: _sketch, height: 150),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: _editSketch,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
        IconButton(
          tooltip: 'Remove drawing',
          onPressed: () => setState(() => _sketch = []),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
        ),
      );
}
