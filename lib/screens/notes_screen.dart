import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../widgets/fx.dart';

const _noteColors = <Color>[
  Color(0x00000000), // default (theme surface)
  Color(0xFFFFF59D),
  Color(0xFFA5D6A7),
  Color(0xFF90CAF9),
  Color(0xFFF48FB1),
  Color(0xFFCE93D8),
  Color(0xFFFFCC80),
];

Color noteColor(BuildContext context, int i) {
  if (i == 0) return Theme.of(context).colorScheme.surfaceContainerHighest;
  final c = _noteColors[i];
  // Soften for dark theme so text stays readable.
  return Theme.of(context).brightness == Brightness.dark
      ? Color.alphaBlend(c.withValues(alpha: 0.25), const Color(0xFF1E1E1E))
      : c;
}

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notes = [...context.watch<DataStore>().notes]..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updated.compareTo(a.updated);
      });
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openNote(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New note'),
      ),
      body: notes.isEmpty
          ? const Center(child: Text('No notes yet.'))
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.1),
              itemCount: notes.length,
              itemBuilder: (_, i) => Reveal(index: i, child: Tilt(child: NoteCard(notes[i]))),
            ),
    );
  }
}

void openNote(BuildContext context, Note? note) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditor(note: note)));
}

class NoteCard extends StatelessWidget {
  const NoteCard(this.note, {super.key});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = (note.color != 0 && !dark) ? Colors.black87 : null;
    return InkWell(
      onTap: () => openNote(context, note),
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: noteColor(context, note.color), borderRadius: BorderRadius.circular(12)),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(note.title.isEmpty ? 'Untitled' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              if (note.pinned) const Icon(Icons.push_pin, size: 16),
            ]),
            const SizedBox(height: 6),
            Expanded(child: Text(note.body, overflow: TextOverflow.fade)),
            if (note.tags.isNotEmpty)
              Text(note.tags.map((e) => '#$e').join(' '), style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, this.note});
  final Note? note;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');
  late final _tags = TextEditingController(text: widget.note?.tags.join(', ') ?? '');
  late int _color = widget.note?.color ?? 0;
  late bool _pinned = widget.note?.pinned ?? false;
  late final String _id = widget.note?.id ?? const Uuid().v4();
  bool _deleted = false;

  Future<void> _save() async {
    if (_deleted) return;
    final empty = _title.text.trim().isEmpty && _body.text.trim().isEmpty;
    final store = context.read<DataStore>();
    if (empty) {
      if (widget.note != null) await store.deleteNote(widget.note!);
      return;
    }
    final n = widget.note ?? Note(id: _id);
    n
      ..title = _title.text.trim()
      ..body = _body.text
      ..color = _color
      ..pinned = _pinned
      ..tags = _tags.text
          .split(',')
          .map((e) => e.trim().replaceAll('#', ''))
          .where((e) => e.isNotEmpty)
          .toList();
    await store.saveNote(n);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = _color == 0 ? null : noteColor(context, _color);
    final fg = (_color != 0 && !dark) ? Colors.black87 : null;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(), // auto-saves when leaving
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          foregroundColor: fg,
          title: const Text('Note'),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Unpin' : 'Pin',
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () => setState(() => _pinned = !_pinned),
            ),
            if (widget.note != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  _deleted = true;
                  await context.read<DataStore>().deleteNote(widget.note!);
                  if (mounted) Navigator.pop(context);
                },
              ),
          ],
        ),
        body: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              TextField(
                controller: _title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                    hintText: 'Title', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
              ),
              Expanded(
                child: TextField(
                  controller: _body,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                      hintText: 'Write something…', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                ),
              ),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                    hintText: 'Tags (comma separated)', prefixIcon: Icon(Icons.tag)),
              ),
              const SizedBox(height: 10),
              Row(children: [
                for (var i = 0; i < _noteColors.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == 0 ? Colors.grey.shade400 : _noteColors[i],
                        border: Border.all(
                            width: _color == i ? 3 : 1,
                            color: _color == i ? Colors.black54 : Colors.black26),
                      ),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
