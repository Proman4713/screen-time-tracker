import 'dart:async';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import '../models/app_usage.dart';
import '../models/app_block.dart';
import 'database_service.dart';
import 'block_service.dart';

/// Service to track the currently active window/process on Windows
class ProcessTrackerService {
  Timer? _trackingTimer;
  Timer? _flushTimer;
  String? _currentProcessName;
  DateTime? _currentProcessStartTime;
  bool _isTickInProgress = false;
  bool _isFlushInProgress = false;
  int _trackingIntervalSeconds = 1;
  final int _flushIntervalSeconds = 5;
  int _idleTimeoutMinutes = 5;
  
  // Notification fields
  bool _enableDailyGoal = false;
  int _dailyGoalHours = 4;
  bool _enableBreakReminders = false;
  int _breakReminderIntervalMinutes = 60;
  
  int _continuousActiveSeconds = 0;
  bool _dailyGoalTriggered = false;

  bool _pauseOnLock = true;
  bool _isTracking = false;
  DateTime? _cachedTotalDate;
  int _cachedTotalSecondsToday = 0;
  DateTime? _cachedProcessTotalsDate;
  DateTime? _pendingUsageDate;
  final Map<String, int> _cachedProcessTotalsToday = {};
  final Map<String, int> _pendingUsageSecondsByProcess = {};
  final Map<String, String> _pendingWindowTitleByProcess = {};
  final Map<String, String?> _pendingAppPathByProcess = {};

  final Map<String, DateTime> _blockGraceStartedAt = {};
  final Map<String, DateTime> _blockCooldownUntil = {};
  final Set<String> _blockFinalWarningSent = {};
  final int _blockGraceSeconds = 20;
  final int _blockCooldownSeconds = 20;

  // Custom ignored apps from user settings
  List<String> customIgnoredApps = [];

  // Blocking Rules
  List<AppBlock> blockRules = [];

  final DatabaseService _databaseService = DatabaseService.instance;

  // Callbacks
  Function(String processName, String windowTitle)? onActiveWindowChanged;
  Function(int totalSecondsToday)? onTotalTimeUpdated;
  Function(int breakMinutes)? onBreakReminderReached;
  Function(int goalHours)? onDailyGoalReached;
  Function(String processName, int graceSeconds)? onBlockedAppGraceStarted;
  Function(String processName, int secondsRemaining)? onBlockedAppGraceWarning;
  Function(String processName)? onBlockedAppAttempt;

  bool get isTracking => _isTracking;
  int get trackingInterval => _trackingIntervalSeconds;

  @visibleForTesting
  static bool matchesRuleProcess(String processName, String ruleProcessName) {
    final normalizedProcess = _normalizeProcessForMatch(processName);
    final normalizedRule = _normalizeProcessForMatch(ruleProcessName);
    if (normalizedProcess.isEmpty || normalizedRule.isEmpty) {
      return false;
    }
    return normalizedProcess == normalizedRule ||
        normalizedProcess.contains(normalizedRule);
  }

  @visibleForTesting
  static bool isTimeInWindowMinutes(int nowMin, int startMin, int endMin) {
    if (startMin <= endMin) {
      return nowMin >= startMin && nowMin <= endMin;
    }
    // Overnight block (e.g., 22:00 to 06:00)
    return nowMin >= startMin || nowMin <= endMin;
  }

  @visibleForTesting
  static int applyUsageDelta(int currentSeconds, int deltaSeconds) {
    if (deltaSeconds <= 0) {
      return currentSeconds;
    }
    return currentSeconds + deltaSeconds;
  }

  static String _normalizeProcessForMatch(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.endsWith('.exe')) {
      return normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  String _normalizeProcessName(String value) {
    return _normalizeProcessForMatch(value);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _syncDailyTotals(DateTime now) async {
    final today = _dateOnly(now);

    if (_cachedTotalDate != null && !_isSameDay(_cachedTotalDate!, today)) {
      await _flushPendingUsage(force: true);
      _pendingUsageDate = null;
      _blockGraceStartedAt.clear();
      _blockCooldownUntil.clear();
      _blockFinalWarningSent.clear();
    }

    if (_cachedTotalDate == null || !_isSameDay(_cachedTotalDate!, today)) {
      _cachedTotalDate = today;
      _cachedTotalSecondsToday = await _databaseService.getTotalUsageForDate(today);
      _dailyGoalTriggered = false;
      onTotalTimeUpdated?.call(_cachedTotalSecondsToday);
    }

    await _syncProcessTotalsForDay(today);
  }

  Future<void> _syncProcessTotalsForDay(DateTime day) async {
    if (_cachedProcessTotalsDate != null && _isSameDay(_cachedProcessTotalsDate!, day)) {
      return;
    }

    final usageForDay = await _databaseService.getUsageForDate(day);
    _cachedProcessTotalsToday
      ..clear()
      ..addEntries(
        usageForDay.map(
          (usage) => MapEntry(
            _normalizeProcessName(usage.processName),
            usage.usageSeconds,
          ),
        ),
      );
    _cachedProcessTotalsDate = day;
  }

  void _bufferUsage(WindowInfo windowInfo, DateTime now) {
    final today = _dateOnly(now);

    if (_pendingUsageDate != null && !_isSameDay(_pendingUsageDate!, today)) {
      unawaited(_flushPendingUsage(force: true));
      _pendingUsageDate = today;
    } else {
      _pendingUsageDate ??= today;
    }

    final process = _normalizeProcessName(windowInfo.processName);
    if (process.isEmpty) {
      return;
    }

    _pendingUsageSecondsByProcess[process] =
        applyUsageDelta(_pendingUsageSecondsByProcess[process] ?? 0, _trackingIntervalSeconds);
    _pendingWindowTitleByProcess[process] = windowInfo.windowTitle;
    if (windowInfo.processPath != null && windowInfo.processPath!.isNotEmpty) {
      _pendingAppPathByProcess[process] = windowInfo.processPath;
    }

    _cachedProcessTotalsToday[process] =
        applyUsageDelta(_cachedProcessTotalsToday[process] ?? 0, _trackingIntervalSeconds);
  }

  Future<void> _flushPendingUsage({bool force = false}) async {
    if (_isFlushInProgress) {
      return;
    }

    if (_pendingUsageSecondsByProcess.isEmpty) {
      return;
    }

    _isFlushInProgress = true;

    final flushDate = _pendingUsageDate ?? _cachedTotalDate ?? _dateOnly(DateTime.now());
    final flushTimestamp = DateTime.now();
    final pendingSeconds = Map<String, int>.from(_pendingUsageSecondsByProcess);
    final pendingTitles = Map<String, String>.from(_pendingWindowTitleByProcess);
    final pendingPaths = Map<String, String?>.from(_pendingAppPathByProcess);

    _pendingUsageSecondsByProcess.clear();
    _pendingWindowTitleByProcess.clear();
    _pendingAppPathByProcess.clear();

    try {
      final entries = pendingSeconds.entries
          .where((entry) => entry.value > 0)
          .map(
            (entry) => AppUsage(
              processName: entry.key,
              windowTitle: pendingTitles[entry.key] ?? entry.key,
              appPath: pendingPaths[entry.key],
              usageSeconds: entry.value,
              date: flushDate,
              lastActive: flushTimestamp,
            ),
          )
          .toList();

      if (entries.isNotEmpty) {
        await _databaseService.upsertAppUsageBatch(entries);
      }
    } catch (e) {
      // Re-queue entries on failure so data is not lost.
      for (final entry in pendingSeconds.entries) {
        _pendingUsageSecondsByProcess[entry.key] =
            applyUsageDelta(_pendingUsageSecondsByProcess[entry.key] ?? 0, entry.value);
      }
      _pendingWindowTitleByProcess.addAll(pendingTitles);
      _pendingAppPathByProcess.addAll(pendingPaths);
      if (!force) {
        debugPrint('Pending usage flush failed: $e');
      }
    } finally {
      _isFlushInProgress = false;
    }
  }

  Future<bool> _handleBlockedProcess(String processName, DateTime now) async {
    final normalizedProcess = _normalizeProcessName(processName);
    if (normalizedProcess.isEmpty) {
      return false;
    }

    final cooldownUntil = _blockCooldownUntil[normalizedProcess];
    if (cooldownUntil != null && now.isBefore(cooldownUntil)) {
      return true;
    }

    final graceStart = _blockGraceStartedAt[normalizedProcess];
    if (graceStart == null) {
      _blockGraceStartedAt[normalizedProcess] = now;
      _blockFinalWarningSent.remove(normalizedProcess);
      onBlockedAppGraceStarted?.call(processName, _blockGraceSeconds);
      return true;
    }

    final elapsed = now.difference(graceStart).inSeconds;
    final remaining = _blockGraceSeconds - elapsed;
    if (remaining > 0) {
      if (remaining <= 5 && !_blockFinalWarningSent.contains(normalizedProcess)) {
        _blockFinalWarningSent.add(normalizedProcess);
        onBlockedAppGraceWarning?.call(processName, remaining);
      }
      return true;
    }

    final blocked = await BlockService.blockProcess(processName);
    _blockGraceStartedAt.remove(normalizedProcess);
    _blockFinalWarningSent.remove(normalizedProcess);
    _blockCooldownUntil[normalizedProcess] =
        now.add(Duration(seconds: _blockCooldownSeconds));

    if (blocked) {
      onBlockedAppAttempt?.call(processName);
    }

    return true;
  }

  void _clearBlockGraceForProcess(String processName) {
    final normalizedProcess = _normalizeProcessName(processName);
    if (normalizedProcess.isEmpty) {
      return;
    }
    _blockGraceStartedAt.remove(normalizedProcess);
    _blockFinalWarningSent.remove(normalizedProcess);
  }

  /// Get the current foreground window information
  WindowInfo? getForegroundWindowInfo() {
    try {
      final hwnd = GetForegroundWindow();
      if (hwnd == 0) return null;

      // Get window title
      final titleLength = GetWindowTextLength(hwnd);
      if (titleLength == 0) return null;

      final titleBuffer = wsalloc(titleLength + 1);
      GetWindowText(hwnd, titleBuffer, titleLength + 1);
      final windowTitle = titleBuffer.toDartString();
      free(titleBuffer);

      // Get process ID
      final processIdPtr = calloc<DWORD>();
      GetWindowThreadProcessId(hwnd, processIdPtr);
      final processId = processIdPtr.value;
      free(processIdPtr);

      if (processId == 0) return null;

      // Open process to get executable path
      final hProcess = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION,
        FALSE,
        processId,
      );

      if (hProcess == 0) return null;

      String processName = 'unknown';
      String? processPath;

      // Get process executable path
      final pathBuffer = wsalloc(MAX_PATH);
      final pathSize = calloc<DWORD>();
      pathSize.value = MAX_PATH;

      if (QueryFullProcessImageName(hProcess, 0, pathBuffer, pathSize) != 0) {
        processPath = pathBuffer.toDartString();
        // Extract just the executable name
        final parts = processPath.split('\\');
        if (parts.isNotEmpty) {
          processName = _normalizeProcessName(parts.last);
        }
      }

      free(pathBuffer);
      free(pathSize);
      CloseHandle(hProcess);

      // Filter out system processes and empty windows
      if (_shouldIgnoreProcess(processName, windowTitle)) {
        return null;
      }

      return WindowInfo(
        processName: processName,
        windowTitle: windowTitle,
        processPath: processPath,
      );
    } catch (e) {
      debugPrint('Error getting foreground window: $e');
      return null;
    }
  }

  bool _shouldIgnoreProcess(String processName, String windowTitle) {
    final normalizedProcess = _normalizeProcessName(processName);

    // Ignore empty or minimal window titles
    if (windowTitle.isEmpty || windowTitle.length < 2) return true;

    // Ignore common system processes
    final ignoredProcesses = [
      'searchhost',
      'shellexperiencehost',
      'startmenuexperiencehost',
      'lockapp',
      'textinputhost',
      'systemsettings',
      'applicationframehost',
    ];

    // Check built-in ignored processes
    if (ignoredProcesses.any(
      (p) => normalizedProcess.contains(p),
    )) {
      return true;
    }

    // Check user-defined ignored apps
    if (customIgnoredApps.any(
      (app) {
        final ignoredProcess = _normalizeProcessName(app);
        if (ignoredProcess.isEmpty) return false;
        return normalizedProcess == ignoredProcess ||
            normalizedProcess.contains(ignoredProcess) ||
            ignoredProcess.contains(normalizedProcess);
      },
    )) {
      return true;
    }

    return false;
  }

  /// Get system idle time in seconds
  int _getIdleTimeSeconds() {
    try {
      final lastInputInfo = calloc<LASTINPUTINFO>();
      lastInputInfo.ref.cbSize = sizeOf<LASTINPUTINFO>();

      if (GetLastInputInfo(lastInputInfo) != 0) {
        final tickCount = GetTickCount();
        final idleMilliseconds = tickCount - lastInputInfo.ref.dwTime;
        free(lastInputInfo);
        return idleMilliseconds ~/ 1000;
      }
      free(lastInputInfo);
    } catch (e) {
      debugPrint('Error getting idle time: $e');
    }
    return 0; // Assume not idle on error
  }

  /// Start tracking active windows
  void startTracking() {
    if (_isTracking) return;

    _isTracking = true;
    _isTickInProgress = false;
    _isFlushInProgress = false;
    _trackingTimer = Timer.periodic(
      Duration(seconds: _trackingIntervalSeconds),
      (_) async {
        if (_isTickInProgress) {
          return;
        }

        _isTickInProgress = true;
        try {
          await _trackActiveWindow();
        } finally {
          _isTickInProgress = false;
        }
      },
    );

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      Duration(seconds: _flushIntervalSeconds),
      (_) {
        unawaited(_flushPendingUsage());
      },
    );

    unawaited(_syncDailyTotals(DateTime.now()));

    debugPrint('Process tracking started');
  }

  /// Stop tracking
  void stopTracking() {
    _isTracking = false;
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _isTickInProgress = false;

    // Save current session before stopping
    unawaited(_saveCurrentSession());
    unawaited(_flushPendingUsage(force: true));
    debugPrint('Process tracking stopped');
  }

  Future<void> _trackActiveWindow() async {
    final now = DateTime.now();
    await _syncDailyTotals(now);

    // Check for user activity early to avoid recording blank usage
    if (_idleTimeoutMinutes > 0) {
      final idleSeconds = _getIdleTimeSeconds();
      if (idleSeconds >= _idleTimeoutMinutes * 60) {
        // User is idle. We should pause tracking for this interval.
        // Also close out any existing session so we don't skew the last active time
        await _saveCurrentSession();
        _continuousActiveSeconds = 0; // Reset consecutive break timer
        return;
      }
    }

    final hwnd = GetForegroundWindow();
    if (_pauseOnLock && hwnd == 0) {
      // If foreground window is 0 (Desktop or Lock Screen in some states) and pauseOnLock is on
      await _saveCurrentSession();
      _continuousActiveSeconds = 0;
      return;
    }

    final windowInfo = getForegroundWindowInfo();
    if (windowInfo == null) return;

    // --- Blocking Check ---
    if (await _shouldBlockProcess(windowInfo.processName)) {
      await _handleBlockedProcess(windowInfo.processName, now);
      return;
    } else {
      _clearBlockGraceForProcess(windowInfo.processName);
    }

    // Check if the active window changed
    if (_currentProcessName != windowInfo.processName) {
      // Save the previous session
      await _saveCurrentSession();

      // Start new session
      _currentProcessName = windowInfo.processName;
      _currentProcessStartTime = now;

      onActiveWindowChanged?.call(
        windowInfo.processName,
        windowInfo.windowTitle,
      );
    }

    // Record usage for current process
    if (_currentProcessName != null) {
      _bufferUsage(windowInfo, now);

      // Update total usage from in-memory cache to avoid per-tick read queries.
      _cachedTotalSecondsToday =
          applyUsageDelta(_cachedTotalSecondsToday, _trackingIntervalSeconds);
      onTotalTimeUpdated?.call(_cachedTotalSecondsToday);

      // --- Notifications Logic ---
      _continuousActiveSeconds += _trackingIntervalSeconds;
      
      // 1. Break Reminders
      if (_enableBreakReminders && _breakReminderIntervalMinutes > 0) {
        if (_continuousActiveSeconds >= _breakReminderIntervalMinutes * 60) {
          onBreakReminderReached?.call(_breakReminderIntervalMinutes);
          _continuousActiveSeconds = 0; // Reset consecutive active timer
        }
      }

      // 2. Daily Goal
      if (_enableDailyGoal && _dailyGoalHours > 0 && !_dailyGoalTriggered) {
        if (_cachedTotalSecondsToday >= _dailyGoalHours * 3600) {
          onDailyGoalReached?.call(_dailyGoalHours);
          _dailyGoalTriggered = true; // Only trigger once per day
        }
      }
    }
  }

  Future<void> _saveCurrentSession() async {
    if (_currentProcessName == null || _currentProcessStartTime == null) return;

    await _flushPendingUsage(force: true);

    // Session data is saved incrementally via buffered ticks and explicit flushes.
    _currentProcessName = null;
    _currentProcessStartTime = null;
  }

  /// Set tracking interval in seconds
  void setTrackingInterval(int seconds) {
    if (seconds <= 0 || _trackingIntervalSeconds == seconds) {
      return;
    }

    _trackingIntervalSeconds = seconds;
    if (_isTracking) {
      stopTracking();
      startTracking();
    }
  }

  /// Set idle timeout in minutes
  void setIdleTimeout(int minutes) {
    if (minutes == _idleTimeoutMinutes) {
      return;
    }
    _idleTimeoutMinutes = minutes;
  }

  void setPauseOnLock(bool value) {
    if (_pauseOnLock == value) {
      return;
    }
    _pauseOnLock = value;
  }

  Future<bool> _shouldBlockProcess(String processName) async {
    final now = DateTime.now();
    final timeNowMin = now.hour * 60 + now.minute;
    final normalizedProcess = _normalizeProcessName(processName);

    for (final rule in blockRules) {
      if (!rule.isEnabled) continue;
      final normalizedRule = _normalizeProcessName(rule.processName);
      if (normalizedRule.isEmpty) continue;

      if (!matchesRuleProcess(normalizedProcess, normalizedRule)) {
        continue;
      }

      // 1. Check Schedule Block
      if (rule.blockStartMinutes != null && rule.blockEndMinutes != null) {
        if (_isTimeBetween(timeNowMin, rule.blockStartMinutes!, rule.blockEndMinutes!)) {
          return true;
        }
      }

      // 2. Check Daily Limit
      if (rule.dailyLimitSeconds != null) {
        final usageToday = _cachedProcessTotalsToday[normalizedRule] ?? 0;
        if (usageToday >= rule.dailyLimitSeconds!) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isTimeBetween(int nowMin, int startMin, int endMin) {
    return isTimeInWindowMinutes(nowMin, startMin, endMin);
  }

  void configureNotifications({
    required bool enableDailyGoal,
    required int dailyGoalHours,
    required bool enableBreakReminders,
    required int breakReminderIntervalMinutes,
  }) {
    _enableDailyGoal = enableDailyGoal;
    _dailyGoalHours = dailyGoalHours;
    _enableBreakReminders = enableBreakReminders;
    _breakReminderIntervalMinutes = breakReminderIntervalMinutes;
  }

  void dispose() {
    stopTracking();
  }
}

/// Information about a window
class WindowInfo {
  final String processName;
  final String windowTitle;
  final String? processPath;

  WindowInfo({
    required this.processName,
    required this.windowTitle,
    this.processPath,
  });

  @override
  String toString() {
    return 'WindowInfo(processName: $processName, windowTitle: $windowTitle)';
  }
}
