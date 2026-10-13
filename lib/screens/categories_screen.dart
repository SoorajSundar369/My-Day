import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/helpers.dart';
import '../data/habit_models.dart';
import '../data/money_store.dart';
import '../widgets/common.dart';

/// Categories, plus the overall monthly budget and per-category budgets.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  Future<double?> _askAmount(BuildContext context, String title, double? current) {
    final c = TextEditingController(text: current == null ? '' : '$current'.replaceAll(RegExp(r'\.0$'), ''));
    return showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount per month (empty = no budget)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, double.tryParse(c.text.trim()) ?? 0),
              child: const Text('Save')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MoneyStore>();
    final now = DateTime.now();

    Widget group(String kind, String title) {
      final list = m.catsOf(kind);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionTitle(context, title,
            trailing: TextButton.icon(
                onPressed: () => showCategoryEditor(context, null, kind),
                icon: const Icon(Icons.add),
                label: const Text('Add'))),
        for (final c in list)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: palette[c.color % palette.length].withValues(alpha: 0.18),
                child: Icon(moneyIcons[c.icon % moneyIcons.length], color: palette[c.color % palette.length]),
              ),
              title: Text(c.name),
              subtitle: kind == 'expense' && m.budgets[c.id] != null
                  ? Text('Budget ${m.fmt(m.budgets[c.id]!)} / month · spent ${m.fmt(m.spentInMonth(now, category: c.id))}')
                  : null,
              onTap: () => showCategoryEditor(context, c, kind),
            ),
          ),
      ]);
    }

    final overall = m.budgets[''];
    return Scaffold(
      appBar: AppBar(title: const Text('Categories & budgets')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Overall monthly budget'),
                subtitle: Text(overall == null
                    ? 'Not set'
                    : '${m.fmt(overall)} · spent ${m.fmt(m.spentInMonth(now))} this month'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final v = await _askAmount(context, 'Overall monthly budget', overall);
                  if (v != null) await m.setBudget('', v);
                },
              ),
            ),
            group('expense', 'Expense categories'),
            group('income', 'Income categories'),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}

Future<void> showCategoryEditor(BuildContext context, ExpenseCategory? cat, String kind) {
  final m = context.read<MoneyStore>();
  final name = TextEditingController(text: cat?.name ?? '');
  final budget = TextEditingController(
      text: cat == null || m.budgets[cat.id] == null ? '' : '${m.budgets[cat.id]}'.replaceAll(RegExp(r'\.0$'), ''));
  var icon = cat?.icon ?? 6;
  var color = cat?.color ?? 0;
  final locked = cat != null && (cat.id == 'other' || cat.id == 'other_income');

  return showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(cat == null ? 'New category' : 'Edit category'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (var i = 0; i < moneyIcons.length; i++)
                  InkWell(
                    onTap: () => setState(() => icon = i),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: icon == i ? palette[color] : Theme.of(ctx).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(10),
                        color: icon == i ? palette[color].withValues(alpha: 0.2) : null,
                      ),
                      child: Icon(moneyIcons[i], size: 20, color: icon == i ? palette[color] : null),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < palette.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => color = i),
                    child: CircleAvatar(
                        radius: 14,
                        backgroundColor: palette[i],
                        child: color == i ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
                  ),
              ]),
              if (kind == 'expense') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: budget,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Monthly budget (optional)', prefixText: '${m.symbol} '),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          if (cat != null && !locked)
            TextButton(
              onPressed: () async {
                await m.deleteCat(cat);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final c = cat ?? ExpenseCategory(id: m.newId(), name: '', kind: kind);
              c
                ..name = name.text.trim()
                ..icon = icon
                ..color = color;
              await m.saveCat(c);
              if (kind == 'expense') await m.setBudget(c.id, double.tryParse(budget.text.trim()));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
