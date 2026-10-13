import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taskme/data/data_store.dart';
import 'package:taskme/data/habit_models.dart';
import 'package:taskme/data/models.dart';
import 'package:taskme/data/money_store.dart';
import 'package:taskme/services/settings_service.dart';

void main() {
  sqfliteFfiInit();

  test('an existing v3 database upgrades to the newest schema and keeps its data', () async {
    final dir = await Directory.systemTemp.createTemp('myday_mig');
    final first = DataStore();
    await first.init(dir: dir, factory: databaseFactoryFfi);
    await first.saveTask(Task(id: 'keep-me', title: 'Existing task'));
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();
    final money = MoneyStore(first, settings);
    await money.load();
    await money.save(Expense(id: 'old-expense', amount: 99, category: 'food'));
    // pretend this database was created by the previous app version
    await first.db.execute('ALTER TABLE expenses DROP COLUMN customName');
    await first.db.setVersion(3);
    await first.db.close();

    final upgraded = DataStore();
    await upgraded.init(dir: dir, factory: databaseFactoryFfi);
    expect(upgraded.tasks.single.title, 'Existing task');
    final cols = (await upgraded.db.rawQuery('PRAGMA table_info(expenses)')).map((r) => r['name']).toList();
    expect(cols, contains('customName'));
    final rows = await upgraded.db.query('expenses');
    expect(rows.single['customName'], '');
    expect(File('${dir.path}/taskme.db.bak-v3').existsSync(), isTrue); // safety copy made
  });

  test('custom (one-off) labels show up instead of the category name', () async {
    final dir = await Directory.systemTemp.createTemp('myday_label');
    final store = DataStore();
    await store.init(dir: dir, factory: databaseFactoryFfi);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();
    final money = MoneyStore(store, settings);
    await money.load();

    final normal = Expense(id: 'a', amount: 10, category: 'food');
    final oneOff = Expense(id: 'b', amount: 20, category: 'other', customName: 'Gym locker');
    await money.save(normal);
    await money.save(oneOff);

    expect(money.labelOf(normal), 'Food');
    expect(money.labelOf(oneOff), 'Gym locker');
    // charts still count the one-off entry under "Other"
    final range = money.rangeFor(Period.all, 0, null);
    expect(money.summarize(range).byCategory['other'], 20);
    expect(money.toCsv([oneOff]), contains('"Gym locker"'));

    // survives a reload from the database
    await money.load();
    expect(money.expenses.firstWhere((e) => e.id == 'b').customName, 'Gym locker');
  });
}
