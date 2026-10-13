import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../data/journal_models.dart';
import '../data/journal_store.dart';
import '../widgets/fx.dart';
import 'drawing_pad.dart';
import 'journal_media.dart';

bool get _mobile => Platform.isAndroid || Platform.isIOS;

class JournalEditor extends StatefulWidget {
  const JournalEditor({super.key, this.entry, this.prompt, this.initialDate, this.onFinished, this.autoRecord = false});

  /// Quick add from a widget: called after saving instead of closing the page.
  final VoidCallback? onFinished;

  /// Start recording a voice note straight away.
  final bool autoRecord;

  /// null = a new entry.
  final JournalEntry? entry;

  /// A writing prompt to start from (becomes the title).
  final String? prompt;

  /// Date for a new entry (defaults to now).
  final DateTime? initialDate;

  @override
  State<JournalEditor> createState() => _JournalEditorState();
}

class _JournalEditorState extends State<JournalEditor> {
  late final JournalStore _journal = context.read<JournalStore>();
  late final String _id = widget.entry?.id ?? const Uuid().v4();
  late final _title = TextEditingController(text: widget.entry?.title ?? widget.prompt ?? '');
  late final _body = TextEditingController(text: widget.entry?.body ?? '');
  late final _tags = TextEditingController(text: widget.entry?.tags.join(', ') ?? '');
  late DateTime _date = widget.entry?.date ?? widget.initialDate ?? DateTime.now();
  late int _mood = widget.entry?.mood ?? 0;
  late String _place = widget.entry?.place ?? '';
  late double? _lat = widget.entry?.lat;
  late double? _lng = widget.entry?.lng;
  late bool _bookmarked = widget.entry?.bookmarked ?? false;
  late final List<JournalMedia> _media = [...?widget.entry?.media];
  final _addedNow = <JournalMedia>[];
  bool _preview = false;
  bool _deleted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoRecord) WidgetsBinding.instance.addPostFrameCallback((_) => _record());
  }

  Future<void> _finishQuick() async {
    await _save();
    widget.onFinished!();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  // ---------- saving ----------
  Future<void> _save() async {
    if (_deleted) return;
    final e = widget.entry ?? JournalEntry(id: _id);
    e
      ..title = _title.text.trim()
      ..body = _body.text
      ..date = _date
      ..mood = _mood
      ..place = _place
      ..lat = _lat
      ..lng = _lng
      ..bookmarked = _bookmarked
      ..tags = _tags.text.split(',').map((t) => t.trim().replaceAll('#', '')).where((t) => t.isNotEmpty).toList()
      ..media = _media;
    if (e.isEmpty) {
      if (widget.entry != null) await _journal.delete(widget.entry!);
      for (final m in _addedNow) {
        await _journal.removeMedia(m);
      }
      return;
    }
    // attachments removed while editing an existing entry are deleted for good
    if (widget.entry != null) {
      final keep = _media.map((m) => m.fileId).toSet();
      for (final m in widget.entry!.media.where((m) => !keep.contains(m.fileId)).toList()) {
        await _journal.removeMedia(m);
      }
    }
    await _journal.save(e);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('The entry and its photos, videos and recordings will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    _deleted = true;
    if (widget.entry != null) await _journal.delete(widget.entry!);
    for (final m in _addedNow) {
      await _journal.removeMedia(m);
    }
    if (mounted) Navigator.pop(context);
  }

  // ---------- text formatting ----------
  void _wrap(String left, [String? right]) {
    right ??= left;
    final t = _body.text;
    var s = _body.selection;
    if (!s.isValid) s = TextSelection.collapsed(offset: t.length);
    final chosen = t.substring(s.start, s.end);
    final inner = chosen.isEmpty ? 'text' : chosen;
    _body.value = TextEditingValue(
      text: t.replaceRange(s.start, s.end, '$left$inner$right'),
      selection: TextSelection(baseOffset: s.start + left.length, extentOffset: s.start + left.length + inner.length),
    );
  }

  void _linePrefix(String prefix) {
    final t = _body.text;
    var s = _body.selection;
    if (!s.isValid) s = TextSelection.collapsed(offset: t.length);
    final lineStart = s.start == 0 ? 0 : t.lastIndexOf('\n', s.start - 1) + 1;
    if (t.startsWith(prefix, lineStart)) {
      _body.value = TextEditingValue(
          text: t.replaceRange(lineStart, lineStart + prefix.length, ''),
          selection: TextSelection.collapsed(offset: (s.start - prefix.length).clamp(0, t.length)));
    } else {
      _body.value = TextEditingValue(
          text: t.replaceRange(lineStart, lineStart, prefix),
          selection: TextSelection.collapsed(offset: s.start + prefix.length));
    }
  }

  // ---------- attachments ----------
  Future<void> _attach(String path, String kind, {String? name}) async {
    final m = await _journal.addMedia(path, kind, name: name);
    if (mounted) {
      setState(() {
        _media.add(m);
        _addedNow.add(m);
      });
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _guard(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _snack('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhotos() => _guard(() async {
        final paths = _mobile
            ? (await ImagePicker().pickMultiImage()).map((f) => f.path).toList()
            : (await FilePicker.pickFiles(type: FileType.image, allowMultiple: true))?.paths.whereType<String>().toList() ?? [];
        for (final path in paths) {
          await _attach(path, 'photo');
        }
      });

  Future<void> _takePhoto() => _guard(() async {
        final f = await ImagePicker().pickImage(source: ImageSource.camera);
        if (f != null) await _attach(f.path, 'photo');
      });

  Future<void> _addVideo() => _guard(() async {
        final String? path = _mobile
            ? (await ImagePicker().pickVideo(source: ImageSource.gallery))?.path
            : (await FilePicker.pickFiles(type: FileType.video))?.files.single.path;
        if (path != null) await _attach(path, 'video');
      });

  Future<void> _draw() async {
    final bytes = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => const DrawingPad()));
    if (bytes == null) return;
    await _guard(() async {
      final f = File(p.join(Directory.systemTemp.path, 'drawing_${DateTime.now().millisecondsSinceEpoch}.png'));
      await f.writeAsBytes(bytes);
      await _attach(f.path, 'drawing', name: 'Handwriting ${DateFormat('d MMM h:mm a').format(DateTime.now())}.png');
      await f.delete();
    });
  }

  Future<void> _record() async {
    final path = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      builder: (_) => const _RecorderSheet(),
    );
    if (path == null) return;
    await _guard(() => _attach(path, 'audio', name: 'Voice note ${DateFormat('d MMM h:mm a').format(DateTime.now())}${p.extension(path)}'));
  }

  Future<void> _addLocation() async {
    if (!_mobile) return _editPlace();
    await _guard(() async {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('Turn on location on your phone first.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _snack('Location permission was not given.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
      var label = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      try {
        final marks = await Geocoding().placemarkFromCoordinates(pos.latitude, pos.longitude).timeout(const Duration(seconds: 8));
        if (marks.isNotEmpty) {
          final m = marks.first;
          final parts = [m.name, m.locality, m.administrativeArea].where((e) => e != null && e.isNotEmpty).toSet();
          if (parts.isNotEmpty) label = parts.join(', ');
        }
      } catch (_) {
        // no place name available: keep the coordinates
      }
      if (mounted) {
        setState(() {
          _place = label;
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
      }
    });
  }

  Future<void> _editPlace() async {
    final c = TextEditingController(text: _place);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Where were you?'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Place')),
        actions: [
          if (_place.isNotEmpty) TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (res == null) return;
    setState(() {
      _place = res;
      if (res.isEmpty) {
        _lat = null;
        _lng = null;
      }
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    setState(() => _date = DateTime(d.year, d.month, d.day, t?.hour ?? _date.hour, t?.minute ?? _date.minute));
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final photos = _media.where((m) => m.kind != 'audio').toList();
    final audios = _media.where((m) => m.kind == 'audio').toList();

    Widget tool(IconData icon, String tip, VoidCallback f) =>
        IconButton(tooltip: tip, icon: Icon(icon, size: 20), onPressed: _preview ? null : f);

    return PopScope(
      canPop: widget.onFinished == null,
      onPopInvokedWithResult: (didPop, _) {
        if (widget.onFinished != null) {
          if (!didPop) _finishQuick();
        } else {
          _save(); // saves when you leave
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry == null ? 'New entry' : 'Entry'),
          actions: [
            IconButton(
              tooltip: _preview ? 'Edit' : 'Preview',
              icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _preview = !_preview),
            ),
            IconButton(
              tooltip: 'Bookmark',
              icon: Icon(_bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: _bookmarked ? cs.primary : null),
              onPressed: () => setState(() => _bookmarked = !_bookmarked),
            ),
            if (widget.entry != null)
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
            TextButton(
                onPressed: () => widget.onFinished != null ? _finishQuick() : Navigator.pop(context),
                child: const Text('Done')),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
              // date + mood
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ActionChip(
                  avatar: const Icon(Icons.event_rounded, size: 18),
                  label: Text(DateFormat('EEE, d MMM y · h:mm a').format(_date)),
                  onPressed: _pickDate,
                ),
                for (var m = 1; m <= 5; m++)
                  Tooltip(
                    message: moodNames[m],
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(() => _mood = _mood == m ? 0 : m),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _mood == m ? cs.primary.withValues(alpha: 0.22) : null,
                          border: Border.all(color: _mood == m ? cs.primary : Colors.transparent, width: 2),
                        ),
                        child: Text(moodEmojis[m], style: TextStyle(fontSize: _mood == m ? 26 : 22)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _title,
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Title (optional)', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
              ),
              // formatting toolbar
              Glass(
                radius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    tool(Icons.format_bold_rounded, 'Bold', () => _wrap('**')),
                    tool(Icons.format_italic_rounded, 'Italic', () => _wrap('*')),
                    tool(Icons.strikethrough_s_rounded, 'Strikethrough', () => _wrap('~~')),
                    tool(Icons.title_rounded, 'Heading', () => _linePrefix('## ')),
                    tool(Icons.format_list_bulleted_rounded, 'Bullet list', () => _linePrefix('- ')),
                    tool(Icons.format_list_numbered_rounded, 'Numbered list', () => _linePrefix('1. ')),
                    tool(Icons.format_quote_rounded, 'Quote', () => _linePrefix('> ')),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              if (_preview)
                Container(
                  constraints: const BoxConstraints(minHeight: 220),
                  padding: const EdgeInsets.all(4),
                  child: _body.text.trim().isEmpty
                      ? Text('Nothing written yet.', style: tt.bodyMedium?.copyWith(color: cs.outline))
                      : MarkdownBody(data: _body.text, selectable: true),
                )
              else
                TextField(
                  controller: _body,
                  minLines: 10,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: tt.bodyLarge?.copyWith(height: 1.55),
                  decoration: const InputDecoration(
                      hintText: 'Write about your day…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false),
                ),
              // attachments
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final m in photos)
                    MediaThumb(m, size: 96, onRemove: () => setState(() => _media.remove(m))),
                ]),
              ],
              if (audios.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 8, children: [
                  for (final m in audios) AudioChip(m, onRemove: () => setState(() => _media.remove(m))),
                ]),
              ],
              if (_place.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    avatar: const Icon(Icons.place_rounded, size: 18),
                    label: Text(_place),
                    onPressed: _editPlace,
                    onDeleted: () => setState(() {
                      _place = '';
                      _lat = null;
                      _lng = null;
                    }),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // add buttons
              Wrap(spacing: 8, runSpacing: 8, children: [
                ActionChip(avatar: const Icon(Icons.photo_outlined, size: 18), label: const Text('Photo'), onPressed: _busy ? null : _addPhotos),
                if (_mobile)
                  ActionChip(avatar: const Icon(Icons.photo_camera_outlined, size: 18), label: const Text('Camera'), onPressed: _busy ? null : _takePhoto),
                ActionChip(avatar: const Icon(Icons.videocam_outlined, size: 18), label: const Text('Video'), onPressed: _busy ? null : _addVideo),
                ActionChip(avatar: const Icon(Icons.mic_none_rounded, size: 18), label: const Text('Voice'), onPressed: _busy ? null : _record),
                ActionChip(avatar: const Icon(Icons.gesture_rounded, size: 18), label: const Text('Write / draw'), onPressed: _busy ? null : _draw),
                ActionChip(
                    avatar: Icon(_mobile ? Icons.my_location_rounded : Icons.place_outlined, size: 18),
                    label: Text(_mobile ? 'Location' : 'Place'),
                    onPressed: _busy ? null : _addLocation),
              ]),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              const SizedBox(height: 14),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(hintText: 'Tags (comma separated)', prefixIcon: Icon(Icons.tag_rounded)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that records a voice note.
class _RecorderSheet extends StatefulWidget {
  const _RecorderSheet();

  @override
  State<_RecorderSheet> createState() => _RecorderSheetState();
}

class _RecorderSheetState extends State<_RecorderSheet> {
  final _rec = AudioRecorder();
  Timer? _tick;
  int _seconds = 0;
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error = 'Microphone permission was not given.');
        return;
      }
      final aac = await _rec.isEncoderSupported(AudioEncoder.aacLc);
      _path = p.join(Directory.systemTemp.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.${aac ? 'm4a' : 'wav'}');
      await _rec.start(RecordConfig(encoder: aac ? AudioEncoder.aacLc : AudioEncoder.wav), path: _path!);
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
    } catch (e) {
      setState(() => _error = 'Could not start recording: $e');
    }
  }

  Future<void> _stop({required bool save}) async {
    _tick?.cancel();
    String? out;
    try {
      out = await _rec.stop();
    } catch (_) {}
    if (!save && out != null) {
      try {
        await File(out).delete();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context, save ? out : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ] else ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _PulseDot(),
              const SizedBox(width: 12),
              Text('Recording  ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(onPressed: () => _stop(save: false), child: const Text('Cancel')),
              const SizedBox(width: 12),
              FilledButton.icon(
                  icon: const Icon(Icons.stop_rounded), label: const Text('Stop & save'), onPressed: () => _stop(save: true)),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
        child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
      );
}
