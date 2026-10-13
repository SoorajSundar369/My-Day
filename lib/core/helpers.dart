import 'package:flutter/material.dart';

import '../data/habit_models.dart';
import 'package:intl/intl.dart';

/// Icons users can pick for habits (index is stored, so never reorder).
const habitIcons = <IconData>[
  Icons.self_improvement, Icons.fitness_center, Icons.water_drop, Icons.menu_book,
  Icons.bedtime, Icons.directions_run, Icons.restaurant, Icons.code,
  Icons.edit, Icons.music_note, Icons.savings, Icons.spa,
  Icons.wb_sunny, Icons.favorite, Icons.psychology, Icons.brush,
  Icons.language, Icons.medication, Icons.school, Icons.park,
  Icons.directions_bike, Icons.no_drinks, Icons.phone_android, Icons.cleaning_services,
];

/// Icons for expense categories (index is stored, so never reorder).
const moneyIcons = <IconData>[
  Icons.restaurant, Icons.directions_bus, Icons.receipt_long, Icons.shopping_bag,
  Icons.local_hospital, Icons.movie, Icons.category, Icons.payments,
  Icons.card_giftcard, Icons.savings, Icons.home, Icons.school,
  Icons.flight, Icons.pets, Icons.local_gas_station, Icons.phone_android,
  Icons.checkroom, Icons.fitness_center, Icons.coffee, Icons.work,
];

const palette = <Color>[
  Color(0xFF4F6BED), Color(0xFF009688), Color(0xFFE91E63), Color(0xFFFF7043),
  Color(0xFF7E57C2), Color(0xFF43A047), Color(0xFF00A3E0), Color(0xFFB8860B),
  Color(0xFFEF5350), Color(0xFF8D6E63),
];

const payMethods = ['Cash', 'UPI', 'Card', 'Bank', 'Other'];

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime parseDayKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// First day of the week containing [d]. [weekStart]: 1 = Monday ... 7 = Sunday.
DateTime startOfWeek(DateTime d, int weekStart) {
  final day = dayOnly(d);
  final diff = (day.weekday - weekStart + 7) % 7;
  return DateTime(day.year, day.month, day.day - diff);
}

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

String money(num v, String symbol, {bool compact = false}) {
  final f = symbol == '₹'
      ? NumberFormat.decimalPattern('en_IN')
      : NumberFormat.decimalPattern('en_US');
  f.minimumFractionDigits = 0;
  f.maximumFractionDigits = 2;
  return '$symbol${f.format(v)}';
}

/// The little picture for a habit: its icon, or its first letter when "No icon" was chosen.
Widget habitGlyph(Habit h, Color color, {double size = 24}) {
  if (h.icon < 0) {
    final letter = h.name.trim().isEmpty ? '?' : h.name.trim().characters.first.toUpperCase();
    return Text(letter, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.85));
  }
  return Icon(habitIcons[h.icon % habitIcons.length], color: color, size: size);
}
