import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service to extract and cache Windows application icons.
class AppIconService {
  static final AppIconService _instance = AppIconService._();
  static AppIconService get instance => _instance;
  AppIconService._();

  /// Cache of process name -> icon file path
  final Map<String, String?> _cache = {};

  /// In-flight icon requests to prevent duplicate extraction work.
  final Map<String, Future<String?>> _inFlight = {};

  /// Directory where extracted icons are stored
  String? _iconDir;

  Future<String> _getIconDir() async {
    if (_iconDir != null) return _iconDir!;
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'app_icons'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _iconDir = dir.path;
    return _iconDir!;
  }

  /// Get the cached icon path for a process name, or extract it.
  /// Returns null if icon extraction fails.
  Future<String?> getIconPath(String processName, {String? executablePath}) async {
    // Normalize
    final key = processName.toLowerCase();

    final pending = _inFlight[key];
    if (pending != null) {
      return pending;
    }

    final request = _getIconPathInternal(
      key: key,
      executablePath: executablePath,
    );
    _inFlight[key] = request;

    try {
      return await request;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<String?> _getIconPathInternal({
    required String key,
    String? executablePath,
  }) async {

    // Check memory cache
    if (_cache.containsKey(key) && _cache[key] != null) {
      return _cache[key];
    }
    if (_cache.containsKey(key) && _cache[key] == null && executablePath == null) {
      return null;
    }

    // Check disk cache
    final dir = await _getIconDir();
    final cachedFile = File(p.join(dir, '$key.png'));
    if (await cachedFile.exists()) {
      _cache[key] = cachedFile.path;
      return cachedFile.path;
    }

    // Prefer direct executable extraction so installed-but-not-running apps work.
    if (executablePath != null && executablePath.isNotEmpty) {
      final extracted = await _extractIconFromExecutable(
        executablePath: executablePath,
        outputPath: cachedFile.path,
      );
      if (extracted && await cachedFile.exists()) {
        _cache[key] = cachedFile.path;
        return cachedFile.path;
      }
    }

    // Fallback to extracting from a currently running process.
    final extractedFromProcess = await _extractIconFromRunningProcess(
      processName: key,
      outputPath: cachedFile.path,
    );
    if (extractedFromProcess && await cachedFile.exists()) {
      _cache[key] = cachedFile.path;
      return cachedFile.path;
    }

    // Mark as failed so we don't retry
    _cache[key] = null;
    return null;
  }

  Future<bool> _extractIconFromExecutable({
    required String executablePath,
    required String outputPath,
  }) async {
    try {
      if (!File(executablePath).existsSync()) {
        return false;
      }

      final escapedExePath = executablePath.replaceAll("'", "''");
      final escapedOutputPath = outputPath.replaceAll("'", "''");
      final script = '''
Add-Type -AssemblyName System.Drawing
\$target = '$escapedExePath'
if (Test-Path \$target) {
  \$icon = [System.Drawing.Icon]::ExtractAssociatedIcon(\$target)
  if (\$icon) {
    \$bmp = \$icon.ToBitmap()
    \$bmp.Save('$escapedOutputPath', [System.Drawing.Imaging.ImageFormat]::Png)
    \$bmp.Dispose()
    \$icon.Dispose()
    Write-Output "OK"
  }
}
''';

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 6));

      return result.exitCode == 0 && result.stdout.toString().trim().contains('OK');
    } catch (_) {
      return false;
    }
  }

  Future<bool> _extractIconFromRunningProcess({
    required String processName,
    required String outputPath,
  }) async {
    try {
      final outputPathEscaped = outputPath.replaceAll('\\', '\\\\');
      final script = '''
Add-Type -AssemblyName System.Drawing
\$process = Get-Process -Name "${processName.replaceAll('.exe', '')}" -ErrorAction SilentlyContinue | Select-Object -First 1
if (\$process -and \$process.MainModule) {
  \$icon = [System.Drawing.Icon]::ExtractAssociatedIcon(\$process.MainModule.FileName)
  if (\$icon) {
    \$bmp = \$icon.ToBitmap()
    \$bmp.Save("$outputPathEscaped", [System.Drawing.Imaging.ImageFormat]::Png)
    \$bmp.Dispose()
    \$icon.Dispose()
    Write-Output "OK"
  }
}
''';

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 5));

      return result.exitCode == 0 && result.stdout.toString().trim().contains('OK');
    } catch (_) {
      return false;
    }
  }

  /// Pre-fetch icons for a list of process names.
  Future<void> prefetchIcons(List<String> processNames) async {
    await Future.wait(
      processNames.map((name) => getIconPath(name)),
    );
  }

  /// Clear the icon cache.
  Future<void> clearCache() async {
    _cache.clear();
    _inFlight.clear();
    final dir = await _getIconDir();
    final d = Directory(dir);
    if (await d.exists()) {
      await d.delete(recursive: true);
      await d.create(recursive: true);
    }
  }
}
