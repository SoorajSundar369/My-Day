import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/helpers.dart';
import '../data/habit_models.dart';
import '../data/money_store.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring entries')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: m.recurring.isEmpty
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Rent, subscriptions, salary…\nAdd them once and they add themselves.',
                      textAlign: TextAlign.center)))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
              for (final r in m.recurring)
                Card(
                  child: ListTile(
                    leading: Icon(r.kind == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                        color: r.kind == 'income' ? Colors.green : Colors.redAccent),
                    title: Text('${m.fmt(r.amount)} · ${m.cat(r.category)?.name ?? r.category}'),
                    subtitle: Text(
                        '${r.freq[0].toUpperCase()}${r.freq.substring(1)} · next ${DateFormat('d MMM y').format(r.next)}${r.note.isEmpty ? '' : ' · ${r.note}'}'),
                    trailing: Switch(
                        value: r.active,
                        onChanged: (v) {
                          r.active = v;
                          m.saveRecurring(r);
                        }),
                    onTap: () => _edit(context, r),
                  ),
                ),
            ]),
    );
  }

  Future<void> _edit(BuildContext context, Recurring? r) {
    final m = context.read<MoneyStore>();
    var kind = r?.kind ?? 'expense';
    final amount = TextEditingController(text: r == null ? '' : '${r.amount}'.replaceAll(RegExp(r'\.0$'), ''));
    final note = TextEditingController(text: r?.note ?? '');
    String? category = r?.category;
    var method = r?.method ?? 'UPI';
    var freq = r?.freq ?? 'monthly';
    var next = r?.next ?? DateTime.now();

    return showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setState) {
        final cats = m.catsOf(kind);
        final sel = cats.any((c) => c.id == category) ? category : cats.first.id;
        return AlertDialog(
          title: Text(r == null ? 'New recurring entry' : 'Edit recurring entry'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Expense')),
                    ButtonSegment(value: 'income', label: Text('Income')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (v) => setState(() {
                    kind = v.first;
                    category = null;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Amount', prefixText: '${m.symbol} '),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: sel,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => category = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: freq,
                  decoration: const InputDecoration(labelText: 'Repeats'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (v) => setState(() => freq = v!),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text('Next: ${DateFormat('d MMM y').format(next)}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: ctx, initialDate: next, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) setState(() => next = DateTime(d.year, d.month, d.day, 9));
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: 'Paid with'),
                  items: [for (final p in payMethods) DropdownMenuItem(value: p, child: Text(p))],
                  onChanged: (v) => setState(() => method = v!),
                ),
                const SizedBox(height: 12),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (e.g. Rent)')),
              ]),
            ),
          ),
          actions: [
            if (r != null)
              TextButton(
                  onPressed: () async {
                    await m.deleteRecurring(r);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Delete')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: (double.tryParse(amount.text.trim()) ?? 0) <= 0
                  ? null
                  : () async {
                      final x = r ??
                          Recurring(id: m.newId(), amount: 0, category: sel!, next: next);
                      x
                        ..amount = double.parse(amount.text.trim())
                        ..kind = kind
                        ..category = sel!
                        ..method = method
                        ..note = note.text.trim()
                        ..freq = freq
                        ..next = next;
                      await m.saveRecurring(x);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }
}
