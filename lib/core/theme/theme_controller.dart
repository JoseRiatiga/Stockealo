import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> initialize() async {
    try {
      final db = await AppDatabase.instance.database;
      final res = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['theme_mode'],
        limit: 1,
      );
      if (res.isNotEmpty) {
        final val = res.first['value'] as String?;
        if (val == 'dark') {
          _themeMode = ThemeMode.dark;
        } else if (val == 'light') {
          _themeMode = ThemeMode.light;
        } else {
          _themeMode = ThemeMode.system;
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    try {
      final db = await AppDatabase.instance.database;
      final val = mode == ThemeMode.dark
          ? 'dark'
          : (mode == ThemeMode.light ? 'light' : 'system');
      await db.insert(
        'app_settings',
        {'key': 'theme_mode', 'value': val},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }
}
