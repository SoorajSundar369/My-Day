class Habit {
  String id;
  String name;
  String note;
  int icon;
  int color; // index into palette
  String type; // check | count
  int target; // for count habits: amount needed per day
  String unit;
  String freq; // daily | weekdays | times
  int weekdays; // bitmask, bit0 = Monday ... bit6 = Sunday (freq == weekdays)
  int timesPerWeek; // freq == times
  String? remindTime; // "HH:mm"
  String lastNotified; // day key of last reminder shown
  bool archived;
  DateTime created;

  Habit({
    required this.id,
    required this.name,
    this.note = '',
    this.icon = 0,
    this.color = 0,
    this.type = 'check',
    this.target = 1,
    this.unit = '',
    this.freq = 'daily',
    this.weekdays = 127,
    this.timesPerWeek = 3,
    this.remindTime,
    this.lastNotified = '',
    this.archived = false,
    DateTime? created,
  }) : created = created ?? DateTime.now();

  bool get isCount => type == 'count';

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'note': note,
        'icon': icon,
        'color': color,
        'type': type,
        'target': target,
        'unit': unit,
        'freq': freq,
        'weekdays': weekdays,
        'times': timesPerWeek,
        'remind': remindTime,
        'lastNotified': lastNotified,
        'archived': archived ? 1 : 0,
        'created': created.millisecondsSinceEpoch,
      };

  factory Habit.fromMap(Map<String, Object?> m) => Habit(
        id: m['id'] as String,
        name: m['name'] as String,
        note: (m['note'] as String?) ?? '',
        icon: m['icon'] as int,
        color: m['color'] as int,
        type: m['type'] as String,
        target: m['target'] as int,
        unit: (m['unit'] as String?) ?? '',
        freq: m['freq'] as String,
        weekdays: m['weekdays'] as int,
        timesPerWeek: m['times'] as int,
        remindTime: m['remind'] as String?,
        lastNotified: (m['lastNotified'] as String?) ?? '',
        archived: m['archived'] == 1,
        created: DateTime.fromMillisecondsSinceEpoch(m['created'] as int),
      );
}

class ExpenseCategory {
  String id;
  String name;
  int icon;
  int color;
  String kind; // expense | income

  ExpenseCategory({
    required this.id,
    required this.name,
    this.icon = 6,
    this.color = 0,
    this.kind = 'expense',
  });

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'icon': icon, 'color': color, 'kind': kind};

  factory ExpenseCategory.fromMap(Map<String, Object?> m) => ExpenseCategory(
        id: m['id'] as String,
        name: m['name'] as String,
        icon: m['icon'] as int,
        color: m['color'] as int,
        kind: m['kind'] as String,
      );
}

class Expense {
  String id;
  double amount;
  String kind; // expense | income
  String category;
  String method;
  String note;
  DateTime date;
  String? fileId; // receipt stored in the file vault
  String? recurringId;
  String customName; // a one-off category label that was not saved as a category

  Expense({
    required this.id,
    required this.amount,
    this.kind = 'expense',
    required this.category,
    this.method = 'Cash',
    this.note = '',
    DateTime? date,
    this.fileId,
    this.recurringId,
    this.customName = '',
  }) : date = date ?? DateTime.now();

  bool get isIncome => kind == 'income';

  Map<String, Object?> toMap() => {
        'id': id,
        'amount': amount,
        'kind': kind,
        'category': category,
        'method': method,
        'note': note,
        'date': date.millisecondsSinceEpoch,
        'fileId': fileId,
        'recurringId': recurringId,
        'customName': customName,
      };

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as String,
        amount: (m['amount'] as num).toDouble(),
        kind: m['kind'] as String,
        category: m['category'] as String,
        method: m['method'] as String,
        note: (m['note'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        fileId: m['fileId'] as String?,
        recurringId: m['recurringId'] as String?,
        customName: (m['customName'] as String?) ?? '',
      );
}

class Recurring {
  String id;
  double amount;
  String kind;
  String category;
  String method;
  String note;
  String freq; // daily | weekly | monthly | yearly
  DateTime next;
  bool active;

  Recurring({
    required this.id,
    required this.amount,
    this.kind = 'expense',
    required this.category,
    this.method = 'Cash',
    this.note = '',
    this.freq = 'monthly',
    required this.next,
    this.active = true,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'amount': amount,
        'kind': kind,
        'category': category,
        'method': method,
        'note': note,
        'freq': freq,
        'next': next.millisecondsSinceEpoch,
        'active': active ? 1 : 0,
      };

  factory Recurring.fromMap(Map<String, Object?> m) => Recurring(
        id: m['id'] as String,
        amount: (m['amount'] as num).toDouble(),
        kind: m['kind'] as String,
        category: m['category'] as String,
        method: m['method'] as String,
        note: (m['note'] as String?) ?? '',
        freq: m['freq'] as String,
        next: DateTime.fromMillisecondsSinceEpoch(m['next'] as int),
        active: m['active'] == 1,
      );

  DateTime advance(DateTime d) => switch (freq) {
        'daily' => DateTime(d.year, d.month, d.day + 1, d.hour, d.minute),
        'weekly' => DateTime(d.year, d.month, d.day + 7, d.hour, d.minute),
        'yearly' => DateTime(d.year + 1, d.month, d.day, d.hour, d.minute),
        _ => DateTime(d.year, d.month + 1, d.day, d.hour, d.minute),
      };
}
