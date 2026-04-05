import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/app_usage.dart';

class DatabaseService {
  static Database? _database;
  static final DatabaseService instance = DatabaseService._init();
  static const int _dbVersion = 2;

  DatabaseService._init();

  String _normalizeProcessName(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.endsWith('.exe')) {
      return normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  AppUsage? _normalizeUsageForWrite(AppUsage usage) {
    final normalizedProcessName = _normalizeProcessName(usage.processName);
    if (normalizedProcessName.isEmpty) {
      return null;
    }

    return usage.copyWith(processName: normalizedProcessName);
  }

  Future<void> _upsertAppUsageOnExecutor(
    DatabaseExecutor executor,
    AppUsage usage, {
    required bool additive,
  }) async {
    final normalizedUsage = _normalizeUsageForWrite(usage);
    if (normalizedUsage == null) {
      return;
    }

    final dateStr = normalizedUsage.date.toIso8601String().split('T')[0];
    final usageUpdateClause = additive
        ? 'usage_seconds = app_usage.usage_seconds + excluded.usage_seconds,'
        : 'usage_seconds = excluded.usage_seconds,';

    await executor.rawInsert(
      '''
      INSERT INTO app_usage (
        process_name,
        window_title,
        app_path,
        usage_seconds,
        date,
        last_active
      )
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(process_name, date) DO UPDATE SET
        $usageUpdateClause
        window_title = excluded.window_title,
        app_path = COALESCE(excluded.app_path, app_usage.app_path),
        last_active = excluded.last_active
      ''',
      [
        normalizedUsage.processName,
        normalizedUsage.windowTitle,
        normalizedUsage.appPath,
        normalizedUsage.usageSeconds,
        dateStr,
        normalizedUsage.lastActive.toIso8601String(),
      ],
    );
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    // Initialize FFI for Windows
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final appDir = await getApplicationSupportDirectory();
    final dbPath = join(appDir.path, 'screen_time.db');

    // Ensure directory exists
    await Directory(appDir.path).create(recursive: true);

    return await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _normalizeLegacyProcessNamesMigration(db);
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE app_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        process_name TEXT NOT NULL,
        window_title TEXT NOT NULL,
        app_path TEXT,
        usage_seconds INTEGER NOT NULL DEFAULT 0,
        date TEXT NOT NULL,
        last_active TEXT NOT NULL,
        UNIQUE(process_name, date)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_date ON app_usage(date)
    ''');

    await db.execute('''
      CREATE INDEX idx_process ON app_usage(process_name)
    ''');

    // Create settings table
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _normalizeLegacyProcessNamesMigration(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE app_usage_migrated (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          process_name TEXT NOT NULL,
          window_title TEXT NOT NULL,
          app_path TEXT,
          usage_seconds INTEGER NOT NULL DEFAULT 0,
          date TEXT NOT NULL,
          last_active TEXT NOT NULL,
          UNIQUE(process_name, date)
        )
      ''');

      await txn.execute('''
        INSERT INTO app_usage_migrated (
          process_name,
          window_title,
          app_path,
          usage_seconds,
          date,
          last_active
        )
        SELECT
          LOWER(
            CASE
              WHEN TRIM(process_name) LIKE '%.exe'
                THEN SUBSTR(TRIM(process_name), 1, LENGTH(TRIM(process_name)) - 4)
              ELSE TRIM(process_name)
            END
          ) AS normalized_process_name,
          COALESCE(MAX(window_title), '') AS window_title,
          MAX(app_path) AS app_path,
          SUM(usage_seconds) AS usage_seconds,
          date,
          MAX(last_active) AS last_active
        FROM app_usage
        WHERE TRIM(process_name) != ''
        GROUP BY
          LOWER(
            CASE
              WHEN TRIM(process_name) LIKE '%.exe'
                THEN SUBSTR(TRIM(process_name), 1, LENGTH(TRIM(process_name)) - 4)
              ELSE TRIM(process_name)
            END
          ),
          date
      ''');

      await txn.execute('DROP TABLE app_usage');
      await txn.execute('ALTER TABLE app_usage_migrated RENAME TO app_usage');

      await txn.execute('''
        CREATE INDEX idx_date ON app_usage(date)
      ''');

      await txn.execute('''
        CREATE INDEX idx_process ON app_usage(process_name)
      ''');
    });
  }

  /// Insert or update app usage record
  Future<void> upsertAppUsage(AppUsage usage) async {
    final db = await database;
    await _upsertAppUsageOnExecutor(db, usage, additive: true);
  }

  /// Insert or replace app usage record for an exact process/date total.
  Future<void> upsertAppUsageAbsolute(AppUsage usage) async {
    final db = await database;
    await _upsertAppUsageOnExecutor(db, usage, additive: false);
  }

  /// Batch upsert additive deltas in a single transaction.
  Future<void> upsertAppUsageBatch(List<AppUsage> usageEntries) async {
    if (usageEntries.isEmpty) {
      return;
    }

    final db = await database;
    await db.transaction((txn) async {
      for (final usage in usageEntries) {
        await _upsertAppUsageOnExecutor(txn, usage, additive: true);
      }
    });
  }

  /// Batch upsert exact totals in a single transaction.
  Future<void> upsertAppUsageAbsoluteBatch(List<AppUsage> usageEntries) async {
    if (usageEntries.isEmpty) {
      return;
    }

    final db = await database;
    await db.transaction((txn) async {
      for (final usage in usageEntries) {
        await _upsertAppUsageOnExecutor(txn, usage, additive: false);
      }
    });
  }

  /// Get all usage for a specific date
  Future<List<AppUsage>> getUsageForDate(DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];

    final results = await db.query(
      'app_usage',
      where: 'date = ?',
      whereArgs: [dateStr],
      orderBy: 'usage_seconds DESC',
    );

    return results.map((map) => AppUsage.fromMap(map)).toList();
  }

  /// Get all recorded usage from the database
  Future<List<AppUsage>> getAllUsage() async {
    final db = await database;

    final results = await db.query(
      'app_usage',
      orderBy: 'date DESC, usage_seconds DESC',
    );

    return results.map((map) => AppUsage.fromMap(map)).toList();
  }

  /// Get usage for date range
  Future<List<AppUsage>> getUsageForDateRange(DateTime start, DateTime end) async {
    final db = await database;
    final startStr = start.toIso8601String().split('T')[0];
    final endStr = end.toIso8601String().split('T')[0];

    final results = await db.query(
      'app_usage',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startStr, endStr],
      orderBy: 'date DESC, usage_seconds DESC',
    );

    return results.map((map) => AppUsage.fromMap(map)).toList();
  }

  /// Get total usage seconds for a date
  Future<int> getTotalUsageForDate(DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];

    final result = await db.rawQuery(
      'SELECT SUM(usage_seconds) as total FROM app_usage WHERE date = ?',
      [dateStr],
    );

    return (result.first['total'] as int?) ?? 0;
  }

  /// Get total usage seconds for an inclusive date range.
  Future<int> getTotalUsageForDateRange(DateTime start, DateTime end) async {
    final db = await database;
    final startStr = start.toIso8601String().split('T')[0];
    final endStr = end.toIso8601String().split('T')[0];

    final result = await db.rawQuery(
      'SELECT SUM(usage_seconds) as total FROM app_usage WHERE date >= ? AND date <= ?',
      [startStr, endStr],
    );

    return (result.first['total'] as int?) ?? 0;
  }

  /// Compare the current N-day window with the previous N-day window.
  /// Returns totals in seconds for both windows.
  Future<Map<String, int>> getPeriodComparison(int days) async {
    final today = DateTime.now();
    final periodEnd = DateTime(today.year, today.month, today.day);
    final currentStart = periodEnd.subtract(Duration(days: days - 1));

    final previousEnd = currentStart.subtract(const Duration(days: 1));
    final previousStart = previousEnd.subtract(Duration(days: days - 1));

    final currentTotal = await getTotalUsageForDateRange(currentStart, periodEnd);
    final previousTotal = await getTotalUsageForDateRange(previousStart, previousEnd);

    return {
      'currentTotalSeconds': currentTotal,
      'previousTotalSeconds': previousTotal,
    };
  }

  /// Get top apps for a date range
  Future<List<Map<String, dynamic>>> getTopApps(DateTime start, DateTime end, {int limit = 10}) async {
    final db = await database;
    final startStr = start.toIso8601String().split('T')[0];
    final endStr = end.toIso8601String().split('T')[0];

    return await db.rawQuery('''
      SELECT process_name, SUM(usage_seconds) as total_seconds
      FROM app_usage
      WHERE date >= ? AND date <= ?
      GROUP BY process_name
      ORDER BY total_seconds DESC
      LIMIT ?
    ''', [startStr, endStr, limit]);
  }

  /// Get daily usage totals for the past N days
  Future<List<Map<String, dynamic>>> getDailyUsage(int days) async {
    final db = await database;
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day);
    final startDate = endDate.subtract(Duration(days: days - 1));
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];

    final rows = await db.rawQuery('''
      SELECT date, SUM(usage_seconds) as total_seconds
      FROM app_usage
      WHERE date >= ? AND date <= ?
      GROUP BY date
      ORDER BY date ASC
    ''', [startStr, endStr]);

    final totalsByDate = <String, int>{};
    for (final row in rows) {
      final date = row['date'] as String?;
      if (date == null || date.isEmpty) {
        continue;
      }
      totalsByDate[date] = (row['total_seconds'] as int?) ?? 0;
    }

    final filled = <Map<String, dynamic>>[];
    for (int i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      final dateStr = date.toIso8601String().split('T')[0];
      filled.add({
        'date': dateStr,
        'total_seconds': totalsByDate[dateStr] ?? 0,
      });
    }

    return filled;
  }

  /// Save a setting
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get a setting
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );

    if (results.isEmpty) return null;
    return results.first['value'] as String;
  }

  /// Delete old records (older than specified days)
  Future<int> deleteOldRecords(int daysToKeep) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
    final cutoffStr = cutoffDate.toIso8601String().split('T')[0];

    return await db.delete(
      'app_usage',
      where: 'date < ?',
      whereArgs: [cutoffStr],
    );
  }

  /// Clear all usage records from the database
  Future<void> clearAllUsage() async {
    final db = await database;
    await db.delete('app_usage');
  }

  /// Close the database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Get usage for a specific process on a specific date
  Future<AppUsage?> getAppUsageForProcess(String processName, DateTime date) async {
    final db = await database;
    final normalizedProcessName = _normalizeProcessName(processName);
    if (normalizedProcessName.isEmpty) {
      return null;
    }

    final dateStr = date.toIso8601String().split('T')[0];

    final results = await db.rawQuery(
      '''
      SELECT
        SUM(usage_seconds) AS usage_seconds,
        MAX(window_title) AS window_title,
        MAX(app_path) AS app_path,
        MAX(last_active) AS last_active
      FROM app_usage
      WHERE date = ?
        AND REPLACE(LOWER(process_name), '.exe', '') = ?
      ''',
      [dateStr, normalizedProcessName],
    );

    if (results.isEmpty) return null;
    final row = results.first;
    final totalSeconds = row['usage_seconds'] as int?;
    if (totalSeconds == null || totalSeconds <= 0) {
      return null;
    }

    return AppUsage(
      processName: normalizedProcessName,
      windowTitle: (row['window_title'] as String?) ?? normalizedProcessName,
      appPath: row['app_path'] as String?,
      usageSeconds: totalSeconds,
      date: DateTime.parse(dateStr),
      lastActive: DateTime.tryParse((row['last_active'] as String?) ?? '') ??
          DateTime.parse(dateStr),
    );
  }
}
