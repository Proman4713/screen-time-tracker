import 'package:flutter_test/flutter_test.dart';
import 'package:screen_time_tracker/services/process_tracker_service.dart';

void main() {
  group('Tracker accumulation accuracy', () {
    test('adds positive deltas deterministically', () {
      var total = 0;
      total = ProcessTrackerService.applyUsageDelta(total, 1);
      total = ProcessTrackerService.applyUsageDelta(total, 2);
      total = ProcessTrackerService.applyUsageDelta(total, 5);

      expect(total, 8);
    });

    test('ignores non-positive deltas', () {
      var total = 10;
      total = ProcessTrackerService.applyUsageDelta(total, 0);
      total = ProcessTrackerService.applyUsageDelta(total, -2);

      expect(total, 10);
    });
  });
}
