import 'package:flutter/material.dart';

import 'fx.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.sub,
    this.number,
    this.format,
  });
  /// When both are set the value counts up from zero instead of showing [value].
  final double? number;
  final String Function(double)? format;
  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final valueStyle = Theme.of(context)
        .textTheme
        .headlineSmall
        ?.copyWith(fontWeight: FontWeight.bold, color: c);
    return Tilt(
      strength: 0.8,
      child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: c), const SizedBox(width: 6)],
            Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium)),
          ]),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: number != null && format != null
                ? AnimatedCount(value: number!, format: format!, style: valueStyle)
                : Text(value, style: valueStyle),
          ),
          if (sub != null)
            Text(sub!, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ),
    );
  }
}

/// Lays children out in equal-width columns that wrap on narrow screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.minWidth = 150});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minWidth).floor().clamp(1, children.length);
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

Widget sectionTitle(BuildContext context, String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(children: [
        Text(t, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (trailing != null) trailing,
      ]),
    );

String pct(double v) => '${(v * 100).round()}%';
