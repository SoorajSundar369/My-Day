import 'dart:convert';

class ChecklistItem {
  String text;
  bool done;
  ChecklistItem(this.text, [this.done = false]);
  Map<String, dynamic> toJson() => {'t': text, 'd': done};
  factory ChecklistItem.fromJson(Map<String, dynamic> j) =>
      ChecklistItem(j['t'] as String, j['d'] as bool);
}

List<String> _tagsFrom(String? s) =>
    (s == null || s.isEmpty) ? [] : s.split(',').where((e) => e.isNotEmpty).toList();

class Task {
  String id;
  String title;
  String description;
  DateTime? due;
  int priority; // 0 low, 1 normal, 2 high
  bool done;
  String repeat; // none, daily, weekly, monthly
  bool remind;
  bool notified;
  List<String> tags;
  List<ChecklistItem> checklist;
  DateTime created;

  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.due,
    this.priority = 1,
    this.done = false,
    this.repeat = 'none',
    this.remind = false,
    this.notified = false,
    List<String>? tags,
    List<ChecklistItem>? checklist,
    DateTime? created,
  })  : tags = tags ?? [],
        checklist = checklist ?? [],
        created = created ?? DateTime.now();

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'due': due?.millisecondsSinceEpoch,
        'priority': priority,
        'done': done ? 1 : 0,
        'repeat': repeat,
        'remind': remind ? 1 : 0,
        'notified': notified ? 1 : 0,
        'tags': tags.join(','),
        'checklist': jsonEncode(checklist.map((e) => e.toJson()).toList()),
        'created': created.millisecondsSinceEpoch,
      };

  factory Task.fromMap(Map<String, Object?> m) => Task(
        id: m['id'] as String,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        due: m['due'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['due'] as int),
        priority: m['priority'] as int,
        done: m['done'] == 1,
        repeat: m['repeat'] as String,
        remind: m['remind'] == 1,
        notified: m['notified'] == 1,
        tags: _tagsFrom(m['tags'] as String?),
        checklist: ((jsonDecode((m['checklist'] as String?) ?? '[]')) as List)
            .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        created: DateTime.fromMillisecondsSinceEpoch(m['created'] as int),
      );
}

class Note {
  String id;
  String title;
  String body;
  int color; // index into note palette
  bool pinned;
  List<String> tags;
  DateTime created;
  DateTime updated;

  Note({
    required this.id,
    this.title = '',
    this.body = '',
    this.color = 0,
    this.pinned = false,
    List<String>? tags,
    DateTime? created,
    DateTime? updated,
  })  : tags = tags ?? [],
        created = created ?? DateTime.now(),
        updated = updated ?? DateTime.now();

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'color': color,
        'pinned': pinned ? 1 : 0,
        'tags': tags.join(','),
        'created': created.millisecondsSinceEpoch,
        'updated': updated.millisecondsSinceEpoch,
      };

  factory Note.fromMap(Map<String, Object?> m) => Note(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        color: m['color'] as int,
        pinned: m['pinned'] == 1,
        tags: _tagsFrom(m['tags'] as String?),
        created: DateTime.fromMillisecondsSinceEpoch(m['created'] as int),
        updated: DateTime.fromMillisecondsSinceEpoch(m['updated'] as int),
      );
}

class VaultFile {
  String id;
  String name;
  String path; // absolute path inside the app vault
  String folder;
  int size;
  List<String> tags;
  DateTime created;

  VaultFile({
    required this.id,
    required this.name,
    required this.path,
    this.folder = '',
    this.size = 0,
    List<String>? tags,
    DateTime? created,
  })  : tags = tags ?? [],
        created = created ?? DateTime.now();

  String get ext {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  bool get isImage => const ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'].contains(ext);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'path': path,
        'folder': folder,
        'size': size,
        'tags': tags.join(','),
        'created': created.millisecondsSinceEpoch,
      };

  factory VaultFile.fromMap(Map<String, Object?> m) => VaultFile(
        id: m['id'] as String,
        name: m['name'] as String,
        path: m['path'] as String,
        folder: (m['folder'] as String?) ?? '',
        size: m['size'] as int,
        tags: _tagsFrom(m['tags'] as String?),
        created: DateTime.fromMillisecondsSinceEpoch(m['created'] as int),
      );
}
