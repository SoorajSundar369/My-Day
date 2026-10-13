import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/journal_models.dart';
import '../data/journal_store.dart';
import '../screens/files_screen.dart' show fmtSize;
import '../sync/sync_service.dart';

Future<void> openExternally(String path) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await OpenFilex.open(path);
  } else {
    await launchUrl(Uri.file(path));
  }
}

/// Opens a photo big, or a video in the device's video player.
Future<void> openMedia(BuildContext context, JournalMedia m) async {
  final store = context.read<JournalStore>();
  final file = store.fileOf(m);
  if (file == null) {
    _download(context, m);
    return;
  }
  if (m.kind == 'photo' || m.kind == 'drawing') {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(child: Center(child: Image.file(file))),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
                color: Colors.white, icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          ),
        ]),
      ),
    );
  } else {
    await openExternally(file.path);
  }
}

void _download(BuildContext context, JournalMedia m) {
  final rec = context.read<JournalStore>().recordOf(m);
  final ok = context.read<SyncService>().downloadFiles([m.fileId]);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Downloading ${rec == null ? m.name : '${m.name} (${fmtSize(rec.size)})'}…'
          : 'This is on your other device. Connect to sync to download it.')));
}

/// A small picture for photos/drawings/videos.
class MediaThumb extends StatelessWidget {
  const MediaThumb(this.media, {super.key, this.size = 84, this.onRemove});
  final JournalMedia media;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<JournalStore>();
    final cs = Theme.of(context).colorScheme;
    final file = store.fileOf(media);
    Widget inner;
    if (file == null) {
      inner = Container(
        color: cs.surfaceContainerHighest,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.cloud_download_outlined),
          Text('Tap to\ndownload', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
        ]),
      );
    } else if (media.kind == 'video') {
      inner = Container(
        color: Colors.black87,
        child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 36)),
      );
    } else {
      inner = Image.file(file, fit: BoxFit.cover, cacheWidth: (size * 2.2).round(), errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined));
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: InkWell(onTap: () => openMedia(context, media), child: inner)),
        if (media.kind == 'drawing')
          const Positioned(left: 6, bottom: 6, child: Icon(Icons.gesture_rounded, size: 16, color: Colors.white70)),
        if (onRemove != null)
          Positioned(
            right: 2,
            top: 2,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Play/pause chip for a voice recording.
class AudioChip extends StatefulWidget {
  const AudioChip(this.media, {super.key, this.onRemove});
  final JournalMedia media;
  final VoidCallback? onRemove;

  @override
  State<AudioChip> createState() => _AudioChipState();
}

class _AudioChipState extends State<AudioChip> {
  AudioPlayer? _player;
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final file = context.read<JournalStore>().fileOf(widget.media);
    if (file == null) {
      _download(context, widget.media);
      return;
    }
    if (_player == null) {
      final p = _player = AudioPlayer();
      _subs.add(p.onPlayerStateChanged.listen((s) => mounted ? setState(() => _playing = s == PlayerState.playing) : null));
      _subs.add(p.onPositionChanged.listen((d) => mounted ? setState(() => _pos = d) : null));
      _subs.add(p.onDurationChanged.listen((d) => mounted ? setState(() => _len = d) : null));
      _subs.add(p.onPlayerComplete.listen((_) => mounted ? setState(() => _pos = Duration.zero) : null));
    }
    if (_playing) {
      await _player!.pause();
    } else {
      await _player!.play(DeviceFileSource(file.path));
    }
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFile = context.watch<JournalStore>().fileOf(widget.media) != null;
    final progress = _len.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _len.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(!hasFile ? Icons.cloud_download_outlined : (_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded), color: cs.primary, size: 30),
          onPressed: _toggle,
        ),
        SizedBox(
          width: 110,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(value: progress, minHeight: 4, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 3),
            Text(_len == Duration.zero ? 'Voice note' : '${_fmt(_pos)} / ${_fmt(_len)}',
                style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
        if (widget.onRemove != null)
          IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: widget.onRemove),
      ]),
    );
  }
}
