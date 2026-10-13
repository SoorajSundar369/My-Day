import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/helpers.dart';
import '../data/data_store.dart';
import '../data/habit_models.dart';
import '../data/money_store.dart';
import '../services/sound_service.dart';
import 'files_screen.dart';

Future<void> showExpenseEditor(BuildContext context, [Expense? e, String kind = 'expense']) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: ExpenseForm(expense: e, kind: kind),
      ),
    ),
  );
}

class ExpenseForm extends StatefulWidget {
  const ExpenseForm({super.key, this.expense, this.kind = 'expense', this.onDone});

  /// Called instead of closing a dialog (used by the home-screen quick add).
  final VoidCallback? onDone;
  final Expense? expense;
  final String kind;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  void _close() => widget.onDone != null ? widget.onDone!() : Navigator.pop(context);

  late String _kind = widget.expense?.kind ?? widget.kind;
  late final _amount = TextEditingController(
      text: widget.expense == null ? '' : '${widget.expense!.amount}'.replaceAll(RegExp(r'\.0$'), ''));
  late final _note = TextEditingController(text: widget.expense?.note ?? '');
  late String? _category = widget.expense?.category;
  late bool _custom = widget.expense?.customName.isNotEmpty ?? false;
  late final _customName = TextEditingController(text: widget.expense?.customName ?? '');
  bool _saveCustom = true;
  late String _method = widget.expense?.method ?? 'Cash';
  late DateTime _date = widget.expense?.date ?? DateTime.now();
  late String? _fileId = widget.expense?.fileId;

  double? get _value => double.tryParse(_amount.text.trim());

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null) {
      setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
    }
  }

  Future<void> _attach() async {
    final res = await FilePicker.pickFiles();
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final data = context.read<DataStore>();
    await data.addFiles([path], folder: 'Receipts');
    setState(() => _fileId = data.files.last.id);
  }

  Future<void> _save() async {
    final money = context.read<MoneyStore>();
    final sound = context.read<SoundService>();
    final isNew = widget.expense == null;
    final cats = money.catsOf(_kind);
    final e = widget.expense ?? Expense(id: money.newId(), amount: 0, category: '');

    var category = _category ?? cats.first.id;
    var customName = '';
    if (_custom) {
      final name = _customName.text.trim();
      final existing = cats.where((c) => c.name.toLowerCase() == name.toLowerCase()).firstOrNull;
      if (existing != null) {
        category = existing.id; // already a category with that name: just use it
      } else if (_saveCustom) {
        final c = ExpenseCategory(
            id: money.newId(), name: name, icon: 6, color: money.cats.length % palette.length, kind: _kind);
        await money.saveCat(c);
        category = c.id;
      } else {
        category = _kind == 'income' ? 'other_income' : 'other';
        customName = name;
      }
    }
    e
      ..amount = _value!
      ..kind = _kind
      ..customName = customName
      ..category = category
      ..method = _method
      ..note = _note.text.trim()
      ..date = _date
      ..fileId = _fileId;
    await money.save(e);
    if (isNew) sound.play(_kind == 'income' ? Sfx.income : Sfx.expense);
    if (mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final money = context.watch<MoneyStore>();
    final cats = money.catsOf(_kind);
    final selected = cats.any((c) => c.id == _category) ? _category : cats.first.id;
    final receipt = context.watch<DataStore>().files.where((f) => f.id == _fileId).firstOrNull;
    final editing = widget.expense != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        title: Text(editing ? 'Edit entry' : 'Add entry'),
        actions: [
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await money.delete(widget.expense!);
                if (context.mounted) _close();
              },
            ),
          IconButton(icon: const Icon(Icons.close), onPressed: _close),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'expense', icon: Icon(Icons.arrow_upward), label: Text('Expense')),
            ButtonSegment(value: 'income', icon: Icon(Icons.arrow_downward), label: Text('Income')),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() {
            _kind = v.first;
            _category = null;
          }),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _amount,
          autofocus: !editing,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Theme.of(context).textTheme.headlineSmall,
          decoration: InputDecoration(labelText: 'Amount', prefixText: '${money.symbol} '),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Text('Category', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in cats)
            ChoiceChip(
              avatar: Icon(moneyIcons[c.icon % moneyIcons.length],
                  size: 18, color: palette[c.color % palette.length]),
              label: Text(c.name),
              selected: !_custom && selected == c.id,
              onSelected: (_) => setState(() {
                _category = c.id;
                _custom = false;
              }),
            ),
          ChoiceChip(
            avatar: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Custom…'),
            selected: _custom,
            onSelected: (_) => setState(() => _custom = true),
          ),
        ]),
        if (_custom) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customName,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Custom category name'),
            onChanged: (_) => setState(() {}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Save for future use'),
            subtitle: Text(_saveCustom
                ? 'It becomes a category you can pick again'
                : 'Used for this entry only (counts under "Other")'),
            value: _saveCustom,
            onChanged: (v) => setState(() => _saveCustom = v),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text(DateFormat('EEE, d MMM y').format(_date)),
          onPressed: _pickDate,
        ),
        const SizedBox(height: 14),
        Text('Paid with', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final m in payMethods)
            ChoiceChip(label: Text(m), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
        ]),
        const SizedBox(height: 14),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        const SizedBox(height: 12),
        if (receipt == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: _attach, icon: const Icon(Icons.attach_file), label: const Text('Attach receipt')),
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(fileIcon(receipt)),
            title: Text(receipt.name, overflow: TextOverflow.ellipsis),
            onTap: () => openVaultFile(context, receipt),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _fileId = null)),
          ),
        const SizedBox(height: 12),
        FilledButton(
            onPressed: (_value ?? 0) > 0 && (!_custom || _customName.text.trim().isNotEmpty) ? _save : null, child: Text(editing ? 'Save' : 'Add')),
      ]),
    );
  }
}
