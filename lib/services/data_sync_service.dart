import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../models/app_usage.dart';
import 'database_service.dart';

enum ExportFormat { json, csv }
enum ImportMode { merge, replace }

class ImportPreview {
  final String filePath;
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int consolidatedRecords;
  final int newRecords;
  final int duplicateRecords;
  final int conflictingRecords;

  const ImportPreview({
    required this.filePath,
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.consolidatedRecords,
    required this.newRecords,
    required this.duplicateRecords,
    required this.conflictingRecords,
  });

  bool get hasChanges => newRecords > 0 || conflictingRecords > 0;
}

class ImportResult {
  final bool success;
  final ImportPreview preview;
  final int importedRecords;
  final int skippedRecords;
  final String message;

  const ImportResult({
    required this.success,
    required this.preview,
    required this.importedRecords,
    required this.skippedRecords,
    required this.message,
  });
}

class _ParsedImportFile {
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final List<AppUsage> records;

  const _ParsedImportFile({
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.records,
  });
}

class DataSyncService {
  final DatabaseService _databaseService = DatabaseService.instance;

  static final DataSyncService _instance = DataSyncService._internal();

  factory DataSyncService() {
    return _instance;
  }

  DataSyncService._internal();

  String _normalizeProcessName(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.endsWith('.exe')) {
      return normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  String _usageKey(String processName, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return '${_normalizeProcessName(processName)}|${day.toIso8601String().split('T')[0]}';
  }

  AppUsage _normalizeUsageRecord(AppUsage usage) {
    return usage.copyWith(
      processName: _normalizeProcessName(usage.processName),
      date: DateTime(usage.date.year, usage.date.month, usage.date.day),
      usageSeconds: usage.usageSeconds < 0 ? 0 : usage.usageSeconds,
    );
  }

  AppUsage _mergeImportedDuplicates(AppUsage current, AppUsage incoming) {
    final useIncomingMetadata = incoming.lastActive.isAfter(current.lastActive);
    return AppUsage(
      processName: current.processName,
      windowTitle: useIncomingMetadata ? incoming.windowTitle : current.windowTitle,
      appPath: useIncomingMetadata ? incoming.appPath ?? current.appPath : current.appPath,
      usageSeconds: current.usageSeconds >= incoming.usageSeconds
          ? current.usageSeconds
          : incoming.usageSeconds,
      date: current.date,
      lastActive: useIncomingMetadata ? incoming.lastActive : current.lastActive,
    );
  }

  AppUsage _resolveMergeConflict(AppUsage existing, AppUsage imported) {
    final useImportedMetadata = imported.lastActive.isAfter(existing.lastActive);
    return AppUsage(
      processName: existing.processName,
      windowTitle: useImportedMetadata ? imported.windowTitle : existing.windowTitle,
      appPath: useImportedMetadata ? imported.appPath ?? existing.appPath : existing.appPath,
      usageSeconds: existing.usageSeconds >= imported.usageSeconds
          ? existing.usageSeconds
          : imported.usageSeconds,
      date: existing.date,
      lastActive: useImportedMetadata ? imported.lastActive : existing.lastActive,
    );
  }

  bool _isSameUsage(AppUsage a, AppUsage b) {
    return _normalizeProcessName(a.processName) == _normalizeProcessName(b.processName) &&
        DateTime(a.date.year, a.date.month, a.date.day) ==
            DateTime(b.date.year, b.date.month, b.date.day) &&
        a.usageSeconds == b.usageSeconds;
  }

  Map<String, AppUsage> _buildUsageMap(List<AppUsage> usageList) {
    final usageByKey = <String, AppUsage>{};

    for (final rawUsage in usageList) {
      final usage = _normalizeUsageRecord(rawUsage);
      if (usage.processName.isEmpty || usage.usageSeconds <= 0) {
        continue;
      }

      final key = _usageKey(usage.processName, usage.date);
      final existing = usageByKey[key];
      if (existing == null) {
        usageByKey[key] = usage;
      } else {
        usageByKey[key] = _mergeImportedDuplicates(existing, usage);
      }
    }

    return usageByKey;
  }

  @visibleForTesting
  String normalizeProcessNameForTesting(String value) {
    return _normalizeProcessName(value);
  }

  @visibleForTesting
  Map<String, AppUsage> consolidateRecordsForTesting(List<AppUsage> usageList) {
    return _buildUsageMap(usageList);
  }

  @visibleForTesting
  Map<String, int> classifyRecordsForTesting({
    required List<AppUsage> importedRecords,
    required List<AppUsage> existingRecords,
  }) {
    final imported = _buildUsageMap(importedRecords).values.toList();
    final existingMap = _buildUsageMap(existingRecords);

    var newRecords = 0;
    var duplicateRecords = 0;
    var conflictingRecords = 0;

    for (final usage in imported) {
      final key = _usageKey(usage.processName, usage.date);
      final existing = existingMap[key];
      if (existing == null) {
        newRecords++;
      } else if (_isSameUsage(existing, usage)) {
        duplicateRecords++;
      } else {
        conflictingRecords++;
      }
    }

    return {
      'new': newRecords,
      'duplicate': duplicateRecords,
      'conflict': conflictingRecords,
    };
  }

  Future<String?> pickImportFilePath({bool lockParentWindow = true}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Screen Time Data',
        type: FileType.custom,
        allowedExtensions: ['json', 'csv'],
        lockParentWindow: lockParentWindow,
      );

      if (result == null || result.files.single.path == null) {
        return null;
      }

      return result.files.single.path!;
    } catch (e) {
      debugPrint('Import file picker failed: $e');
      return null;
    }
  }

  Future<ImportPreview?> previewImportFile(String filePath) async {
    try {
      final parsed = await _readImportFile(filePath);
      final preview = await _buildPreview(filePath, parsed);
      return preview;
    } catch (e) {
      return null;
    }
  }

  Future<ImportResult> importData(
    String filePath, {
    required ImportMode mode,
  }) async {
    try {
      final parsed = await _readImportFile(filePath);
      final preview = await _buildPreview(filePath, parsed);
      if (parsed.records.isEmpty) {
        return ImportResult(
          success: false,
          preview: preview,
          importedRecords: 0,
          skippedRecords: 0,
          message: 'No valid records found in selected file.',
        );
      }

      if (mode == ImportMode.replace) {
        await _databaseService.clearAllUsage();
        await _databaseService.upsertAppUsageAbsoluteBatch(parsed.records);
        return ImportResult(
          success: true,
          preview: preview,
          importedRecords: parsed.records.length,
          skippedRecords: 0,
          message:
              'Imported ${parsed.records.length} records using Replace mode.',
        );
      }

      final existingMap = _buildUsageMap(await _databaseService.getAllUsage());
      final updates = <AppUsage>[];
      var importedCount = 0;
      var skippedCount = 0;

      for (final imported in parsed.records) {
        final key = _usageKey(imported.processName, imported.date);
        final existing = existingMap[key];
        if (existing == null) {
          updates.add(imported);
          existingMap[key] = imported;
          importedCount++;
          continue;
        }

        if (_isSameUsage(existing, imported)) {
          skippedCount++;
          continue;
        }

        final resolved = _resolveMergeConflict(existing, imported);
        if (_isSameUsage(existing, resolved) &&
            existing.lastActive == resolved.lastActive &&
            existing.windowTitle == resolved.windowTitle &&
            existing.appPath == resolved.appPath) {
          skippedCount++;
          continue;
        }

        updates.add(resolved);
        existingMap[key] = resolved;
        importedCount++;
      }

      if (updates.isNotEmpty) {
        await _databaseService.upsertAppUsageAbsoluteBatch(updates);
      }

      return ImportResult(
        success: true,
        preview: preview,
        importedRecords: importedCount,
        skippedRecords: skippedCount,
        message:
            'Merge complete: $importedCount updated or inserted, $skippedCount skipped as duplicates.',
      );
    } catch (e) {
      return ImportResult(
        success: false,
        preview: const ImportPreview(
          filePath: '',
          totalRows: 0,
          validRows: 0,
          invalidRows: 0,
          consolidatedRecords: 0,
          newRecords: 0,
          duplicateRecords: 0,
          conflictingRecords: 0,
        ),
        importedRecords: 0,
        skippedRecords: 0,
        message: 'Import failed: $e',
      );
    }
  }

  Future<ImportPreview> _buildPreview(
    String filePath,
    _ParsedImportFile parsed,
  ) async {
    final existingMap = _buildUsageMap(await _databaseService.getAllUsage());

    var newRecords = 0;
    var duplicateRecords = 0;
    var conflictingRecords = 0;

    for (final usage in parsed.records) {
      final key = _usageKey(usage.processName, usage.date);
      final existing = existingMap[key];
      if (existing == null) {
        newRecords++;
      } else if (_isSameUsage(existing, usage)) {
        duplicateRecords++;
      } else {
        conflictingRecords++;
      }
    }

    return ImportPreview(
      filePath: filePath,
      totalRows: parsed.totalRows,
      validRows: parsed.validRows,
      invalidRows: parsed.invalidRows,
      consolidatedRecords: parsed.records.length,
      newRecords: newRecords,
      duplicateRecords: duplicateRecords,
      conflictingRecords: conflictingRecords,
    );
  }

  Future<_ParsedImportFile> _readImportFile(String filePath) async {
    final file = File(filePath);
    final extension = file.path.split('.').last.toLowerCase();
    final contentSize = await file.length();
    if (contentSize == 0) {
      return const _ParsedImportFile(
        totalRows: 0,
        validRows: 0,
        invalidRows: 0,
        records: [],
      );
    }

    final content = await file.readAsString();
    if (extension == 'json') {
      final parsed = _parseJsonContent(content);
      final consolidated = _buildUsageMap(parsed.records).values.toList();
      return _ParsedImportFile(
        totalRows: parsed.totalRows,
        validRows: parsed.validRows,
        invalidRows: parsed.invalidRows,
        records: consolidated,
      );
    }

    if (extension == 'csv') {
      final parsed = _parseCsvContent(content);
      final consolidated = _buildUsageMap(parsed.records).values.toList();
      return _ParsedImportFile(
        totalRows: parsed.totalRows,
        validRows: parsed.validRows,
        invalidRows: parsed.invalidRows,
        records: consolidated,
      );
    }

    throw UnsupportedError('Unsupported file format: .$extension');
  }

  _ParsedImportFile _parseJsonContent(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return const _ParsedImportFile(
        totalRows: 0,
        validRows: 0,
        invalidRows: 0,
        records: [],
      );
    }

    final records = <AppUsage>[];
    var invalidRows = 0;

    for (final item in decoded) {
      try {
        if (item is! Map) {
          invalidRows++;
          continue;
        }

        final map = Map<String, dynamic>.from(item);
        final processName =
            (map['process_name'] ?? map['processName'] ?? '').toString().trim();
        final windowTitle =
            (map['window_title'] ?? map['windowTitle'] ?? '').toString();
        final appPathRaw = (map['app_path'] ?? map['appPath'])?.toString();
        final usageSeconds =
            int.tryParse((map['usage_seconds'] ?? map['usageSeconds'] ?? '0').toString()) ??
                0;
        final dateRaw = (map['date'] ?? '').toString();
        final lastActiveRaw =
            (map['last_active'] ?? map['lastActive'] ?? '').toString();

        if (processName.isEmpty || dateRaw.isEmpty) {
          invalidRows++;
          continue;
        }

        final date = DateTime.parse(dateRaw);
        final lastActive = lastActiveRaw.isEmpty
            ? DateTime(date.year, date.month, date.day)
            : DateTime.parse(lastActiveRaw);

        records.add(
          AppUsage(
            processName: processName,
            windowTitle: windowTitle.isEmpty ? processName : windowTitle,
            appPath: appPathRaw?.isEmpty == true ? null : appPathRaw,
            usageSeconds: usageSeconds,
            date: date,
            lastActive: lastActive,
          ),
        );
      } catch (_) {
        invalidRows++;
      }
    }

    return _ParsedImportFile(
      totalRows: decoded.length,
      validRows: records.length,
      invalidRows: invalidRows,
      records: records,
    );
  }

  _ParsedImportFile _parseCsvContent(String content) {
    final csvTable = CsvCodec().decode(content);
    if (csvTable.length <= 1) {
      return const _ParsedImportFile(
        totalRows: 0,
        validRows: 0,
        invalidRows: 0,
        records: [],
      );
    }

    final records = <AppUsage>[];
    var invalidRows = 0;

    for (int i = 1; i < csvTable.length; i++) {
      final row = csvTable[i];
      if (row.length < 7) {
        invalidRows++;
        continue;
      }

      try {
        final processName = row[1].toString().trim();
        final windowTitle = row[2].toString();
        final appPathRaw = row[3]?.toString();
        final usageSeconds = int.tryParse(row[4].toString()) ?? 0;
        final date = DateTime.parse(row[5].toString());
        final lastActive = DateTime.parse(row[6].toString());

        if (processName.isEmpty) {
          invalidRows++;
          continue;
        }

        records.add(
          AppUsage(
            processName: processName,
            windowTitle: windowTitle.isEmpty ? processName : windowTitle,
            appPath: appPathRaw?.isEmpty == true ? null : appPathRaw,
            usageSeconds: usageSeconds,
            date: date,
            lastActive: lastActive,
          ),
        );
      } catch (_) {
        invalidRows++;
      }
    }

    return _ParsedImportFile(
      totalRows: csvTable.length - 1,
      validRows: records.length,
      invalidRows: invalidRows,
      records: records,
    );
  }

  /// Export existing AppUsage data to the local disk in the chosen format.
  /// Returns `true` if successful, `false` otherwise.
  Future<bool> exportData(ExportFormat format) async {
    try {
      final usageLogs = await _databaseService.getAllUsage();
      if (usageLogs.isEmpty) return false;

      final extension = format == ExportFormat.json ? 'json' : 'csv';
      
      // Let user pick save destination
      final String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Screen Time Data',
        fileName: 'screen_time_export.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
      );

      if (selectedPath == null) {
        return false; // User canceled the picker
      }

      final file = File(selectedPath);
      
      if (format == ExportFormat.json) {
        // Convert logs to JSON maps
        final jsonList = usageLogs.map((log) => log.toMap()).toList();
        final jsonString = JsonEncoder.withIndent('  ').convert(jsonList);
        await file.writeAsString(jsonString);
      } else {
        // Convert to CSV
        final List<List<dynamic>> csvData = [
          // Header
          ['ID', 'Process Name', 'Window Title', 'App Path', 'Usage Seconds', 'Date', 'Last Active'],
          // Rows
          ...usageLogs.map((log) => [
            log.id,
            log.processName,
            log.windowTitle,
            log.appPath,
            log.usageSeconds,
            log.date.toIso8601String().split('T')[0],
            log.lastActive.toIso8601String()
          ])
        ];
        
        final csvString = CsvCodec().encode(csvData);
        await file.writeAsString(csvString);
      }
      
      return true;
    } catch (e) {
      debugPrint('Export error: $e');
      return false;
    }
  }

  /// Import external JSON or CSV backup data into the sql database.
  @Deprecated('Use pickImportFilePath + previewImportFile/importData with mode.')
  Future<bool> importDataLegacy() async {
    try {
      final filePath = await pickImportFilePath();
      if (filePath == null) {
        return false;
      }
      final result = await importData(filePath, mode: ImportMode.merge);
      return result.success;
    } catch (_) {
      return false;
    }
  }
}
