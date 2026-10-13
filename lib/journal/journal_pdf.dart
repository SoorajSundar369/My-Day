import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../data/journal_models.dart';
import '../data/journal_store.dart';
import '../services/settings_service.dart';
import 'journal_media.dart';

/// The one export: your whole journal as a single PDF, oldest entry first.
Future<void> exportJournalPdf(BuildContext context) async {
  final journal = context.read<JournalStore>();
  final settings = context.read<SettingsService>();
  final messenger = ScaffoldMessenger.of(context);
  if (journal.entries.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Your journal is empty. Write an entry first.')));
    return;
  }
  messenger.showSnackBar(const SnackBar(content: Text('Making your PDF…'), duration: Duration(seconds: 3)));
  try {
    final bytes = await _build(journal, settings);
    final name = 'MyDay-Journal-${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    final mobile = Platform.isAndroid || Platform.isIOS;
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save your journal',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: mobile ? bytes : null,
    );
    if (path == null) return;
    if (!mobile) {
      await File(path).writeAsBytes(bytes);
      await openExternally(path);
    }
    messenger.showSnackBar(const SnackBar(content: Text('Journal saved as PDF')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not make the PDF: $e')));
  }
}

Future<Uint8List> _shrink(File f) async {
  final codec = await ui.instantiateImageCodec(await f.readAsBytes(), targetWidth: 900);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

List<pw.InlineSpan> _inline(String text, pw.TextStyle base, pw.Font bold) {
  final parts = text.split('**');
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty)
        pw.TextSpan(
          text: parts[i].replaceAll(RegExp(r'(\*|~~|_)'), ''),
          style: i.isOdd ? base.copyWith(font: bold) : base,
        ),
  ];
}

List<pw.Widget> _markdown(String body, pw.Font regular, pw.Font bold) {
  final base = pw.TextStyle(font: regular, fontSize: 11.5, lineSpacing: 3);
  final out = <pw.Widget>[];
  for (final raw in body.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      out.add(pw.SizedBox(height: 6));
    } else if (line.startsWith('#')) {
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
        child: pw.Text(line.replaceFirst(RegExp(r'^#+\s*'), ''), style: pw.TextStyle(font: bold, fontSize: 14)),
      ));
    } else if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12),
        child: pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: '•  ', style: base), ..._inline(line.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''), base, bold)])),
      ));
    } else if (RegExp(r'^\s*\d+\.\s+').hasMatch(line)) {
      final m = RegExp(r'^\s*(\d+\.)\s+(.*)$').firstMatch(line)!;
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12),
        child: pw.RichText(text: pw.TextSpan(children: [pw.TextSpan(text: '${m.group(1)}  ', style: base), ..._inline(m.group(2)!, base, bold)])),
      ));
    } else if (line.startsWith('>')) {
      out.add(pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 3),
        padding: const pw.EdgeInsets.only(left: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: PdfColors.grey500, width: 2))),
        child: pw.RichText(text: pw.TextSpan(children: _inline(line.replaceFirst(RegExp(r'^>\s*'), ''), base.copyWith(color: PdfColors.grey700), bold))),
      ));
    } else {
      out.add(pw.RichText(text: pw.TextSpan(children: _inline(line, base, bold))));
    }
  }
  return out;
}

Future<Uint8List> _build(JournalStore journal, SettingsService settings) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-Bold.ttf'));
  final entries = [...journal.entries]..sort((a, b) => a.date.compareTo(b.date));
  final doc = pw.Document(title: 'My Journal', author: settings.name);

  final widgets = <pw.Widget>[
    pw.Center(
      child: pw.Column(children: [
        pw.SizedBox(height: 60),
        pw.Text('My Journal', style: pw.TextStyle(font: bold, fontSize: 34)),
        pw.SizedBox(height: 8),
        if (settings.name.isNotEmpty) pw.Text(settings.name, style: pw.TextStyle(font: regular, fontSize: 16)),
        pw.SizedBox(height: 6),
        pw.Text(
            '${DateFormat('d MMM y').format(entries.first.date)} – ${DateFormat('d MMM y').format(entries.last.date)}  ·  ${entries.length} entries',
            style: pw.TextStyle(font: regular, fontSize: 11, color: PdfColors.grey700)),
        pw.SizedBox(height: 40),
      ]),
    ),
  ];

  for (final e in entries) {
    final head = pw.TextStyle(font: bold, fontSize: 12, color: PdfColors.blueGrey800);
    final meta = <String>[
      DateFormat('EEEE, d MMMM y · h:mm a').format(e.date),
      if (e.mood > 0) 'Mood: ${moodNames[e.mood]}',
      if (e.place.isNotEmpty) 'Place: ${e.place}',
      if (e.bookmarked) 'Bookmarked',
    ];
    final images = <pw.Widget>[];
    final others = <String>[];
    for (final m in e.media) {
      final f = journal.fileOf(m);
      if ((m.kind == 'photo' || m.kind == 'drawing') && f != null) {
        try {
          images.add(pw.Container(
            margin: const pw.EdgeInsets.only(top: 8, right: 8),
            child: pw.Image(pw.MemoryImage(await _shrink(f)), height: 210, fit: pw.BoxFit.contain),
          ));
        } catch (_) {
          others.add('Picture: ${m.name} (could not be included)');
        }
      } else if (m.kind == 'video') {
        others.add('Video: ${m.name}');
      } else if (m.kind == 'audio') {
        others.add('Voice note: ${m.name}');
      } else {
        others.add('Picture not on this device: ${m.name}');
      }
    }
    widgets.add(pw.Container(
      margin: const pw.EdgeInsets.only(top: 18),
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.6))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(meta.join('   |   '), style: head),
        if (e.title.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(e.title, style: pw.TextStyle(font: bold, fontSize: 17))),
        pw.SizedBox(height: 6),
        ..._markdown(e.body, regular, bold),
        if (images.isNotEmpty) pw.Wrap(children: images),
        for (final o in others) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text(o, style: pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.grey700))),
        if (e.tags.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text(e.tags.map((t) => '#$t').join('  '), style: pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.blue700))),
      ]),
    ));
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    footer: (c) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('${c.pageNumber} / ${c.pagesCount}', style: pw.TextStyle(font: regular, fontSize: 9, color: PdfColors.grey600)),
    ),
    build: (_) => widgets,
  ));
  return doc.save();
}
