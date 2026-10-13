import 'dart:io';

/// A small rolling log of what sync is doing, kept in memory and in a file
/// (`sync.log` next to the database) so problems can be diagnosed.
class SyncLog {
  static final _lines = <String>[];
  static File? _file;

  static Future<void> init(Directory dir) async {
    try {
      final f = File('${dir.path}/sync.log');
      if (await f.exists() && await f.length() > 60 * 1024) await f.delete();
      _file = f;
      add('--- app started ---');
    } catch (_) {}
  }

  static void add(String message) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    final line = '$t $message';
    _lines.add(line);
    if (_lines.length > 300) _lines.removeAt(0);
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  static String dump({int last = 60}) =>
      _lines.length <= last ? _lines.join('\n') : _lines.sublist(_lines.length - last).join('\n');
}
