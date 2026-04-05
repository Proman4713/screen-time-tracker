import 'dart:io';
import 'package:flutter/foundation.dart';

class BlockService {
  static Future<bool> blockProcess(String processName) async {
    if (!Platform.isWindows) return false;

    try {
      // Ensure we don't accidentally kill the tracker itself
      if (processName.toLowerCase().contains('screen_time_tracker')) {
        return false;
      }

        final imageName = processName.toLowerCase().endsWith('.exe')
          ? processName
          : '$processName.exe';
        final result = await Process.run('taskkill', ['/F', '/IM', imageName]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error killing process $processName: $e');
      return false;
    }
  }
}
