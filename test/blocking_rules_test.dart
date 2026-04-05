import 'package:flutter_test/flutter_test.dart';
import 'package:screen_time_tracker/services/process_tracker_service.dart';

void main() {
  group('Blocking rule matching', () {
    test('matches process names regardless of case and .exe suffix', () {
      expect(ProcessTrackerService.matchesRuleProcess('Code.exe', 'code'), isTrue);
      expect(ProcessTrackerService.matchesRuleProcess('chrome', 'CHROME.EXE'), isTrue);
      expect(ProcessTrackerService.matchesRuleProcess('msedge', 'edge'), isTrue);
    });

    test('does not match unrelated process names', () {
      expect(ProcessTrackerService.matchesRuleProcess('notepad', 'chrome'), isFalse);
      expect(ProcessTrackerService.matchesRuleProcess('spotify', ''), isFalse);
    });
  });

  group('Time window checks', () {
    test('supports same-day windows', () {
      // 09:00 to 17:00
      expect(ProcessTrackerService.isTimeInWindowMinutes(9 * 60, 9 * 60, 17 * 60), isTrue);
      expect(ProcessTrackerService.isTimeInWindowMinutes(12 * 60, 9 * 60, 17 * 60), isTrue);
      expect(ProcessTrackerService.isTimeInWindowMinutes(18 * 60, 9 * 60, 17 * 60), isFalse);
    });

    test('supports overnight windows', () {
      // 22:00 to 06:00
      expect(ProcessTrackerService.isTimeInWindowMinutes(23 * 60, 22 * 60, 6 * 60), isTrue);
      expect(ProcessTrackerService.isTimeInWindowMinutes(2 * 60, 22 * 60, 6 * 60), isTrue);
      expect(ProcessTrackerService.isTimeInWindowMinutes(14 * 60, 22 * 60, 6 * 60), isFalse);
    });
  });
}
