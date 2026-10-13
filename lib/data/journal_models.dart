import 'dart:convert';

/// One attachment of a journal entry. The bytes live in the file vault
/// (folder ".journal"), so they sync like any other file.
class JournalMedia {
  JournalMedia({required this.fileId, required this.kind, required this.name});

  final String fileId;

  /// photo | video | audio | drawing
  final String kind;
  final String name;

  Map<String, Object?> toJson() => {'f': fileId, 'k': kind, 'n': name};
  factory JournalMedia.fromJson(Map<String, dynamic> j) =>
      JournalMedia(fileId: j['f'] as String, kind: j['k'] as String, name: (j['n'] as String?) ?? '');
}

class JournalEntry {
  JournalEntry({
    required this.id,
    this.title = '',
    this.body = '',
    DateTime? date,
    this.mood = 0,
    this.place = '',
    this.lat,
    this.lng,
    this.bookmarked = false,
    List<String>? tags,
    List<JournalMedia>? media,
    DateTime? created,
  })  : date = date ?? DateTime.now(),
        tags = tags ?? [],
        media = media ?? [],
        created = created ?? DateTime.now();

  String id;
  String title;

  /// Written in simple Markdown (**bold**, *italic*, lists…), so it syncs as plain text.
  String body;
  DateTime date;

  /// 0 = not set, 1 (very unpleasant) … 5 (very pleasant)
  int mood;
  String place;
  double? lat;
  double? lng;
  bool bookmarked;
  List<String> tags;
  List<JournalMedia> media;
  DateTime created;

  bool get hasPlace => place.isNotEmpty || lat != null;
  bool has(String kind) => media.any((m) => m.kind == kind);
  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty && media.isEmpty;

  int get wordCount {
    final t = '$title $body'.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'date': date.millisecondsSinceEpoch,
        'mood': mood,
        'place': place,
        'lat': lat,
        'lng': lng,
        'bookmarked': bookmarked ? 1 : 0,
        'tags': tags.join(','),
        'media': jsonEncode(media.map((m) => m.toJson()).toList()),
        'created': created.millisecondsSinceEpoch,
      };

  factory JournalEntry.fromMap(Map<String, Object?> m) => JournalEntry(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        mood: (m['mood'] as int?) ?? 0,
        place: (m['place'] as String?) ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        bookmarked: m['bookmarked'] == 1,
        tags: ((m['tags'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toList(),
        media: [
          for (final j in jsonDecode((m['media'] as String?) ?? '[]') as List)
            JournalMedia.fromJson(Map<String, dynamic>.from(j as Map)),
        ],
        created: DateTime.fromMillisecondsSinceEpoch((m['created'] as int?) ?? 0),
      );
}

const moodEmojis = ['', '😞', '🙁', '😐', '🙂', '😄'];
const moodNames = ['Not set', 'Very unpleasant', 'Unpleasant', 'Neutral', 'Pleasant', 'Very pleasant'];

/// Gentle questions to help when you do not know what to write.
const writingPrompts = <String>[
  'What made you smile today?',
  'What are you grateful for right now?',
  'Describe the best part of your day.',
  'What is something you learned recently?',
  'Who made a difference to you this week, and how?',
  'What is on your mind that you have not said out loud?',
  'What would make tomorrow a good day?',
  'Describe a small moment you want to remember.',
  'What are you proud of lately?',
  'What is something you are looking forward to?',
  'What is a worry you could let go of today?',
  'Write about a place that makes you feel calm.',
  'What did you do today that was just for you?',
  'What is one thing you would tell your younger self?',
  'How are you really feeling, and why?',
  'What was the hardest part of today, and how did you handle it?',
  'What is a habit you want to start or stop?',
  'Describe someone you love in three words, then say why.',
  'What would you do if you knew you could not fail?',
  'What is something small that went right today?',
];
