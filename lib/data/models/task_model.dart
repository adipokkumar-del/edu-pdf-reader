class CheckItem {
  CheckItem({required this.text, this.done = false});

  String text;
  bool done;

  Map<String, dynamic> toJson() => {'t': text, 'd': done};

  factory CheckItem.fromJson(Map<String, dynamic> json) => CheckItem(
        text: json['t'] as String? ?? '',
        done: json['d'] as bool? ?? false,
      );
}

class TaskModel {
  TaskModel({
    required this.id,
    this.title = '',
    this.body = '',
    List<CheckItem>? items,
    this.remindAt,
    this.alarm = false,
    this.repeatDaily = false,
    this.completed = false,
    DateTime? createdAt,
  })  : items = items ?? [],
        createdAt = createdAt ?? DateTime.now();

  final int id;
  String title;
  String body;
  List<CheckItem> items;
  DateTime? remindAt;
  bool alarm;
  bool repeatDaily;
  bool completed;
  final DateTime createdAt;

  /// Fits in 31 bits because Android uses it as the alarm id.
  static int newId() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) % 2000000000;

  int get doneCount => items.where((i) => i.done).length;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    if (body.trim().isNotEmpty) return body.trim().split('\n').first;
    if (items.isNotEmpty) return items.first.text;
    return 'Untitled';
  }

  /// Text shown in the reminder notification.
  String get reminderText {
    if (body.trim().isNotEmpty) return body.trim();
    if (items.isNotEmpty) return '${items.length - doneCount} of ${items.length} items left';
    return 'Tap to open';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'items': [for (final i in items) i.toJson()],
        'at': remindAt?.millisecondsSinceEpoch,
        'alarm': alarm,
        'daily': repeatDaily,
        'done': completed,
        'created': createdAt.millisecondsSinceEpoch,
      };

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final at = json['at'] as int?;
    return TaskModel(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      items: [
        for (final i in (json['items'] as List? ?? const []))
          CheckItem.fromJson(i as Map<String, dynamic>),
      ],
      remindAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      alarm: json['alarm'] as bool? ?? false,
      repeatDaily: json['daily'] as bool? ?? false,
      completed: json['done'] as bool? ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['created'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
}

String formatWhen(DateTime d, {bool daily = false}) {
  if (daily) return 'Daily · ${formatTime(d)}';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  final label = diff == 0
      ? 'Today'
      : diff == 1
          ? 'Tomorrow'
          : '${d.day} ${_months[d.month - 1]}';
  return '$label · ${formatTime(d)}';
}
