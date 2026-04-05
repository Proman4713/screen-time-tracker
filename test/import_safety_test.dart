import 'package:flutter_test/flutter_test.dart';
import 'package:screen_time_tracker/models/app_usage.dart';
import 'package:screen_time_tracker/services/data_sync_service.dart';

void main() {
  final service = DataSyncService();

  AppUsage usage({
    required String process,
    required int seconds,
    required DateTime date,
    DateTime? lastActive,
  }) {
    return AppUsage(
      processName: process,
      windowTitle: process,
      usageSeconds: seconds,
      date: date,
      lastActive: lastActive ?? date,
    );
  }

  group('Import safety helpers', () {
    test('normalizes process names', () {
      expect(service.normalizeProcessNameForTesting('Code.EXE'), 'code');
      expect(service.normalizeProcessNameForTesting('  chrome  '), 'chrome');
    });

    test('consolidates duplicate process/day rows', () {
      final day = DateTime(2026, 4, 1);
      final consolidated = service.consolidateRecordsForTesting([
        usage(process: 'Code.exe', seconds: 120, date: day, lastActive: DateTime(2026, 4, 1, 10)),
        usage(process: 'code', seconds: 90, date: day, lastActive: DateTime(2026, 4, 1, 9)),
      ]);

      expect(consolidated.length, 1);
      final entry = consolidated.values.single;
      expect(entry.processName, 'code');
      expect(entry.usageSeconds, 120);
    });

    test('classifies new, duplicate, and conflicting rows', () {
      final day = DateTime(2026, 4, 1);

      final existing = [
        usage(process: 'code', seconds: 120, date: day),
        usage(process: 'chrome', seconds: 300, date: day),
      ];

      final imported = [
        usage(process: 'Code.exe', seconds: 120, date: day), // duplicate
        usage(process: 'chrome', seconds: 450, date: day), // conflict
        usage(process: 'slack.exe', seconds: 30, date: day), // new
      ];

      final result = service.classifyRecordsForTesting(
        importedRecords: imported,
        existingRecords: existing,
      );

      expect(result['duplicate'], 1);
      expect(result['conflict'], 1);
      expect(result['new'], 1);
    });
  });
}
