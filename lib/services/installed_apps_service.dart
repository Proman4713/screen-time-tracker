import 'dart:async';
import 'dart:convert';
import 'dart:io';

class InstalledApp {
  final String displayName;
  final String processName;
  final String? executablePath;

  InstalledApp({
    required this.displayName,
    required this.processName,
    this.executablePath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstalledApp &&
          runtimeType == other.runtimeType &&
          processName.toLowerCase() == other.processName.toLowerCase();

  @override
  int get hashCode => processName.toLowerCase().hashCode;
}

class RunningApp {
  final String processName;
  final String windowTitle;

  RunningApp({
    required this.processName,
    required this.windowTitle,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunningApp &&
          runtimeType == other.runtimeType &&
          processName.toLowerCase() == other.processName.toLowerCase();

  @override
  int get hashCode => processName.toLowerCase().hashCode;
}

class InstalledAppsService {
  static List<InstalledApp>? _cachedInstalledApps;
  static DateTime? _lastInstalledAppsFetchUtc;
  static const Duration _installedAppsCacheTtl = Duration(minutes: 5);
  static const Duration _installedAppsFetchTimeout = Duration(seconds: 12);

  static const String _installedAppsPowerShellScript = r'''
$ErrorActionPreference = 'SilentlyContinue'

$startMenuPaths = @(
  (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
  (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
)

$shell = New-Object -ComObject WScript.Shell

$apps = foreach ($path in $startMenuPaths) {
  if (-not (Test-Path $path)) { continue }

  Get-ChildItem -Path $path -Recurse -Filter *.lnk -ErrorAction SilentlyContinue |
    ForEach-Object {
      try {
        $shortcut = $shell.CreateShortcut($_.FullName)
        $target = $shortcut.TargetPath

        if (
          -not [string]::IsNullOrWhiteSpace($target) -and
          (Test-Path $target) -and
          ([System.IO.Path]::GetExtension($target).ToLowerInvariant() -eq '.exe')
        ) {
          [PSCustomObject]@{
            displayName = $_.BaseName
            processName = [System.IO.Path]::GetFileName($target)
            executablePath = $target
          }
        }
      } catch {
      }
    }
}

$apps |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_.processName) } |
  Sort-Object processName -Unique |
  ConvertTo-Json -Compress -Depth 3
''';

  /// Returns installed desktop applications discovered from Start Menu shortcuts.
  /// Falls back to currently running apps when discovery yields no results.
  static Future<List<InstalledApp>> getInstalledApps({
    bool forceRefresh = false,
  }) async {
    if (!Platform.isWindows) {
      return [];
    }

    if (!forceRefresh && _cachedInstalledApps != null && _lastInstalledAppsFetchUtc != null) {
      final cacheAge = DateTime.now().toUtc().difference(_lastInstalledAppsFetchUtc!);
      if (cacheAge <= _installedAppsCacheTtl) {
        return List<InstalledApp>.from(_cachedInstalledApps!);
      }
    }

    List<InstalledApp> installedApps = [];

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        _installedAppsPowerShellScript,
      ]).timeout(_installedAppsFetchTimeout);

      if (result.exitCode == 0) {
        installedApps = _parseInstalledAppsJson(result.stdout.toString());
      }
    } on TimeoutException {
      // Timeout falls through to running-app fallback below.
    } catch (e) {
      // Ignore and fallback below.
    }

    if (installedApps.isEmpty) {
      final runningApps = await getRunningApps();
      installedApps = runningApps
          .map(
            (app) => InstalledApp(
              displayName: app.windowTitle,
              processName: app.processName,
            ),
          )
          .toSet()
          .toList();
      installedApps.sort((a, b) => a.processName.compareTo(b.processName));
    }

    _cachedInstalledApps = List<InstalledApp>.from(installedApps);
    _lastInstalledAppsFetchUtc = DateTime.now().toUtc();

    return installedApps;
  }

  static List<InstalledApp> _parseInstalledAppsJson(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) {
      return [];
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return [];
    }

    final entries = <dynamic>[];
    if (decoded is List) {
      entries.addAll(decoded);
    } else if (decoded is Map) {
      entries.add(decoded);
    } else {
      return [];
    }

    final apps = <InstalledApp>[];
    final seen = <String>{};

    for (final entry in entries) {
      if (entry is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(entry);
      var processName = (map['processName'] ?? '').toString().trim();
      final displayNameRaw = (map['displayName'] ?? '').toString().trim();
      final executablePathRaw = (map['executablePath'] ?? '').toString().trim();

      if (processName.isEmpty) {
        continue;
      }

      if (!processName.toLowerCase().endsWith('.exe')) {
        processName = '$processName.exe';
      }

      final processKey = processName.toLowerCase();
      if (seen.contains(processKey)) {
        continue;
      }
      seen.add(processKey);

      apps.add(
        InstalledApp(
          displayName: displayNameRaw.isEmpty ? processName : displayNameRaw,
          processName: processName,
          executablePath: executablePathRaw.isEmpty ? null : executablePathRaw,
        ),
      );
    }

    apps.sort((a, b) {
      final byName = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      if (byName != 0) {
        return byName;
      }
      return a.processName.toLowerCase().compareTo(b.processName.toLowerCase());
    });

    return apps;
  }

  /// Fetches a list of currently running applications that have observable window titles.
  static Future<List<RunningApp>> getRunningApps() async {
    final apps = <RunningApp>[];

    if (!Platform.isWindows) {
      return apps;
    }

    try {
      // Use powershell to get processes with main window titles
      // This filters out background services and generic host processes
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-Process | Where-Object { \$_.MainWindowTitle -ne "" } | Select-Object Name, MainWindowTitle | ConvertTo-Csv -NoTypeInformation'
      ]);

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        
        // Skip header line (index 0)
        for (int i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;

          // CSV parsing for "Name","MainWindowTitle"
          final parts = line.split('","');
          if (parts.length >= 2) {
            String processName = parts[0].replaceAll('"', '');
            // Append .exe as that's what we usually track in the process tracker
            if (!processName.toLowerCase().endsWith('.exe')) {
              processName += '.exe';
            }
            
            final windowTitle = parts[1].replaceAll('"', '');

            // Filter out self and common system overlays
            final lowerName = processName.toLowerCase();
            if (lowerName != 'screen_time_tracker.exe' &&
                lowerName != 'textinputhost.exe' &&
                lowerName != 'applicationframehost.exe') {
              apps.add(RunningApp(
                processName: processName,
                windowTitle: windowTitle,
              ));
            }
          }
        }
      }
    } catch (e) {
      // Fallback or error logging
    }

    // Convert to Set and back to List to remove duplicates (based on processName)
    final uniqueApps = apps.toSet().toList();
    
    // Sort alphabetically by processName
    uniqueApps.sort((a, b) => a.processName.compareTo(b.processName));
    
    return uniqueApps;
  }
}
