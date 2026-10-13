import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/data_store.dart';
import '../data/models.dart';
import '../sync/sync_service.dart';
import '../widgets/fx.dart';

IconData fileIcon(VaultFile f) => switch (f.ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'bmp' || 'webp' => Icons.image_outlined,
      'doc' || 'docx' || 'txt' || 'rtf' || 'odt' => Icons.description_outlined,
      'xls' || 'xlsx' || 'csv' => Icons.table_chart_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      'zip' || 'rar' || '7z' => Icons.folder_zip_outlined,
      'mp3' || 'wav' || 'm4a' => Icons.audiotrack_outlined,
      'mp4' || 'mkv' || 'mov' || 'avi' => Icons.movie_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

Future<void> openVaultFile(BuildContext context, VaultFile f) async {
  // The record may have synced without the file itself (it is on the other device).
  if (!context.read<DataStore>().hasLocalFile(f)) {
    final ok = context.read<SyncService>().downloadFiles([f.id]);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Downloading ${f.name} (${fmtSize(f.size)})…'
            : 'This file is on your other device. Connect to sync to download it.')));
    return;
  }
  if (f.isImage) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Stack(children: [
          InteractiveViewer(child: Image.file(File(f.path))),
          Positioned(
              right: 4,
              top: 4,
              child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))),
        ]),
      ),
    );
  } else if (Platform.isAndroid || Platform.isIOS) {
    await OpenFilex.open(f.path);
  } else {
    await launchUrl(Uri.file(f.path));
  }
}

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String? _folder; // null = all

  Future<void> _add() async {
    final res = await FilePicker.pickFiles(allowMultiple: true);
    if (res == null || !mounted) return;
    await context
        .read<DataStore>()
        .addFiles(res.paths.whereType<String>().toList(), folder: _folder ?? '');
  }

  Future<void> _editMeta(VaultFile f) async {
    final folder = TextEditingController(text: f.folder);
    final tags = TextEditingController(text: f.tags.join(', '));
    final name = TextEditingController(text: f.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit file info'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: folder, decoration: const InputDecoration(labelText: 'Folder')),
          const SizedBox(height: 10),
          TextField(controller: tags, decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    f
      ..name = name.text.trim().isEmpty ? f.name : name.text.trim()
      ..folder = folder.text.trim()
      ..tags = tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await context.read<DataStore>().saveFileMeta(f);
  }

  Future<void> _confirmDelete(VaultFile f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('"${f.name}" will be removed from the vault.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<DataStore>().deleteFile(f);
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<DataStore>().visibleFiles;
    final folders = {for (final f in all) if (f.folder.isNotEmpty) f.folder}.toList()..sort();
    final shown = all.where((f) => _folder == null || f.folder == _folder).toList()
      ..sort((a, b) => b.created.compareTo(a.created));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.upload_file),
        label: const Text('Add files'),
      ),
      body: Column(children: [
        if (folders.isNotEmpty)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: const Text('All'),
                      selected: _folder == null,
                      onSelected: (_) => setState(() => _folder = null)),
                ),
                for (final f in folders)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                        avatar: const Icon(Icons.folder, size: 16),
                        label: Text(f),
                        selected: _folder == f,
                        onSelected: (_) => setState(() => _folder = f)),
                  ),
              ],
            ),
          ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('No files yet. Add PDFs, images, documents…'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final f = shown[i];
                    return Reveal(index: i, child: Card(
                      child: ListTile(
                        leading: Icon(context.read<DataStore>().hasLocalFile(f) ? fileIcon(f) : Icons.cloud_download_outlined, size: 30),
                        title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          if (!context.read<DataStore>().hasLocalFile(f)) 'Tap to download',
                          fmtSize(f.size),
                          DateFormat('d MMM y').format(f.created),
                          if (f.folder.isNotEmpty) f.folder,
                          ...f.tags.map((t) => '#$t'),
                        ].join('  ·  ')),
                        onTap: () => openVaultFile(context, f),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            switch (v) {
                              case 'open':
                                openVaultFile(context, f);
                              case 'show':
                                Process.run('explorer', ['/select,', f.path]);
                              case 'edit':
                                _editMeta(f);
                              case 'delete':
                                _confirmDelete(f);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'open', child: Text('Open')),
                            if (Platform.isWindows)
                              const PopupMenuItem(value: 'show', child: Text('Show in folder')),
                            const PopupMenuItem(value: 'edit', child: Text('Rename / folder / tags')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    ));
                  },
                ),
        ),
      ]),
    );
  }
}
