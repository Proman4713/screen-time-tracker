import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/app_usage.dart';
import '../services/database_service.dart';
import '../services/process_tracker_service.dart';
import '../services/notification_service.dart';
import '../models/app_block.dart';
import 'settings_provider.dart';

class ScreenTimeProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService.instance;
  final ProcessTrackerService _processTracker = ProcessTrackerService();

  // Current state
  bool _isTracking = false;
  String _currentApp = '';
  String _currentWindowTitle = '';
  int _liveTodayTotalSeconds = 0;
  int _totalSecondsToday = 0;
  int _currentPeriodTotalSeconds = 0;
  int _previousPeriodTotalSeconds = 0;
  DateTime _selectedDate = DateTime.now();
  int _selectedDays = 1; // 1 = today, common ranges: 7, 14, 30
  bool _isAscending = false;
  int _dataRetentionDays = 30;

  // Usage data
  List<AppUsage> _todayUsage = [];
  List<AggregatedAppUsage> _aggregatedUsage = [];
  List<Map<String, dynamic>> _dailyUsage = [];
  int _dailyUsageWindowDays = 7;
  List<String> _productiveApps = [];

  // Getters
  bool get isTracking => _isTracking;
  String get currentApp => _currentApp;
  String get currentWindowTitle => _currentWindowTitle;
  int get liveTodayTotalSeconds => _liveTodayTotalSeconds;
  int get totalSecondsToday => _totalSecondsToday;
  int get currentPeriodTotalSeconds => _currentPeriodTotalSeconds;
  int get previousPeriodTotalSeconds => _previousPeriodTotalSeconds;
  DateTime get selectedDate => _selectedDate;
  int get selectedDays => _selectedDays;
  bool get isAscending => _isAscending;
  List<AppUsage> get todayUsage => _todayUsage;
  List<AggregatedAppUsage> get aggregatedUsage => _aggregatedUsage;
  List<Map<String, dynamic>> get dailyUsage => _dailyUsage;
  int get dailyUsageWindowDays => _dailyUsageWindowDays;

  String get formattedTotalTime {
    final hours = _totalSecondsToday ~/ 3600;
    final minutes = (_totalSecondsToday % 3600) ~/ 60;
    final seconds = _totalSecondsToday % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  double get focusScore {
    if (_totalSecondsToday == 0) return 100.0;

    int productiveSeconds = 0;
    for (final app in _aggregatedUsage) {
      if (_isProductive(app.processName) || _isProductive(app.displayName)) {
        productiveSeconds += app.totalSeconds;
      }
    }

    return (productiveSeconds / _totalSecondsToday) * 100;
  }

  bool _isProductive(String name) {
    return _productiveApps.any((app) =>
        name.toLowerCase().contains(app.toLowerCase()));
  }

  ScreenTimeProvider({SettingsProvider? initialSettings}) {
    if (initialSettings != null) {
      applySettings(initialSettings, notifyListenersIfNeeded: false);
    }
    _initialize();
  }

  String _normalizeProcessToken(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.endsWith('.exe')) {
      return normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  void applySettings(
    SettingsProvider settings, {
    bool notifyListenersIfNeeded = true,
  }) {
    setTrackingInterval(settings.trackingInterval);
    setIdleTimeout(settings.idleTimeout);
    setIgnoredApps(settings.ignoredApps);

    final productiveChanged =
        !listEquals(_productiveApps, settings.productiveApps);
    if (productiveChanged) {
      _productiveApps = List<String>.from(settings.productiveApps);
    }

    configureNotifications(
      enableDailyGoal: settings.enableDailyGoal,
      dailyGoalHours: settings.dailyGoalHours,
      enableBreakReminders: settings.enableBreakReminders,
      breakReminderIntervalMinutes: settings.breakReminderInterval,
    );

    setPauseOnLock(settings.pauseOnLock);
    setBlockRules(settings.blockRules);
    setShowNotifications(settings.showNotifications);

    if (_dataRetentionDays != settings.dataRetentionDays) {
      _dataRetentionDays = settings.dataRetentionDays;
      unawaited(pruneOldData());
    }

    if (productiveChanged && notifyListenersIfNeeded) {
      notifyListeners();
    }
  }

  Future<void> _initialize() async {
    // Set up callbacks
    _processTracker.onActiveWindowChanged = (processName, windowTitle) {
      _currentApp = processName;
      _currentWindowTitle = windowTitle;
      notifyListeners();
    };

    _processTracker.onTotalTimeUpdated = (totalSeconds) {
      final liveChanged = _liveTodayTotalSeconds != totalSeconds;
      _liveTodayTotalSeconds = totalSeconds;

      var selectedRangeChanged = false;
      if (_selectedDays == 1 && _totalSecondsToday != totalSeconds) {
        _totalSecondsToday = totalSeconds;
        _currentPeriodTotalSeconds = totalSeconds;
        selectedRangeChanged = true;
      }

      if (liveChanged || selectedRangeChanged) {
        notifyListeners();
      }
    };

    _processTracker.onBreakReminderReached = (minutes) {
      NotificationService().showBreakReminder(minutes);
    };

    _processTracker.onDailyGoalReached = (hours) {
      NotificationService().showDailyGoalReached(hours);
    };

    _processTracker.onBlockedAppGraceStarted = (processName, graceSeconds) {
      NotificationService().showBlockGraceStarted(processName, graceSeconds);
    };

    _processTracker.onBlockedAppGraceWarning = (processName, secondsRemaining) {
      NotificationService().showBlockGraceWarning(processName, secondsRemaining);
    };

    _processTracker.onBlockedAppAttempt = (processName) {
      NotificationService().showBlockedApp(processName);
    };

    // Load initial data
    await loadTodayData();
    await loadPeriodComparison(_selectedDays);
    await loadDailyUsage();

    // Auto-prune old data
    await pruneOldData();

    // Auto-start tracking
    startTracking();
  }

  void startTracking() {
    _processTracker.startTracking();
    _isTracking = true;
    notifyListeners();
  }

  void stopTracking() {
    _processTracker.stopTracking();
    _isTracking = false;
    notifyListeners();
  }

  void toggleTracking() {
    if (_isTracking) {
      stopTracking();
    } else {
      startTracking();
    }
  }

  void toggleSortOrder() {
    _isAscending = !_isAscending;
    _sortAggregatedUsage();
    notifyListeners();
  }

  void _sortAggregatedUsage() {
    if (_isAscending) {
      _aggregatedUsage.sort((a, b) => a.totalSeconds.compareTo(b.totalSeconds));
    } else {
      _aggregatedUsage.sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));
    }
  }

  // Methods to update settings
  void setTrackingInterval(int seconds) {
    _processTracker.setTrackingInterval(seconds);
  }

  void setIdleTimeout(int minutes) {
    _processTracker.setIdleTimeout(minutes);
  }

  void setIgnoredApps(List<String> apps) {
    final normalizedApps = apps
        .map(_normalizeProcessToken)
        .where((app) => app.isNotEmpty)
        .toList();
    if (listEquals(_processTracker.customIgnoredApps, normalizedApps)) {
      return;
    }
    _processTracker.customIgnoredApps = normalizedApps;
  }

  void configureNotifications({
    required bool enableDailyGoal,
    required int dailyGoalHours,
    required bool enableBreakReminders,
    required int breakReminderIntervalMinutes,
  }) {
    _processTracker.configureNotifications(
      enableDailyGoal: enableDailyGoal,
      dailyGoalHours: dailyGoalHours,
      enableBreakReminders: enableBreakReminders,
      breakReminderIntervalMinutes: breakReminderIntervalMinutes,
    );
  }

  void setProductiveApps(List<String> apps) {
    final normalizedApps = apps
        .map((app) => app.trim())
        .where((app) => app.isNotEmpty)
        .toList();
    if (listEquals(_productiveApps, normalizedApps)) {
      return;
    }
    _productiveApps = normalizedApps;
    notifyListeners();
  }

  void setPauseOnLock(bool value) {
    _processTracker.setPauseOnLock(value);
  }

  void setBlockRules(List<AppBlock> rules) {
    _processTracker.blockRules = List<AppBlock>.from(rules);
  }

  void setShowNotifications(bool value) {
    NotificationService().setEnabled(value);
  }

  Future<void> setDataRetentionDays(int days) async {
    if (_dataRetentionDays == days) return;
    _dataRetentionDays = days;
    await pruneOldData();
    notifyListeners();
  }

  Future<void> pruneOldData() async {
    try {
      final deletedCount = await _databaseService.deleteOldRecords(_dataRetentionDays);
      if (deletedCount > 0) {
        debugPrint('Pruned $deletedCount old records (Retention: $_dataRetentionDays days)');
        await loadDailyUsage(_dailyUsageWindowDays);
      }
    } catch (e) {
      debugPrint('Error pruning old data: $e');
    }
  }

  int get trackingInterval => _processTracker.trackingInterval;

  Future<void> loadTodayData() async {
    final today = DateTime.now();
    final startDate = DateTime(today.year, today.month, today.day);
    final endDate = startDate;

    await _loadUsageData(startDate, endDate);
  }

  Future<void> loadDataForDays(int days) async {
    _selectedDays = days;
    final today = DateTime.now();
    final endDate = DateTime(today.year, today.month, today.day);
    final startDate = endDate.subtract(Duration(days: days - 1));

    await _loadUsageData(startDate, endDate, notifyListenersIfNeeded: false);

    // Keep "Today" range in sync with live tracker ticks when available.
    if (days == 1 && _liveTodayTotalSeconds > _totalSecondsToday) {
      _totalSecondsToday = _liveTodayTotalSeconds;
    }

    await loadPeriodComparison(days, notifyListenersIfNeeded: false);

    if (days == 1 && _currentPeriodTotalSeconds < _totalSecondsToday) {
      _currentPeriodTotalSeconds = _totalSecondsToday;
    }

    notifyListeners();
  }

  Future<void> loadPeriodComparison(
    int days, {
    bool notifyListenersIfNeeded = true,
  }) async {
    final comparison = await _databaseService.getPeriodComparison(days);
    _currentPeriodTotalSeconds = comparison['currentTotalSeconds'] ?? 0;
    _previousPeriodTotalSeconds = comparison['previousTotalSeconds'] ?? 0;
    if (notifyListenersIfNeeded) {
      notifyListeners();
    }
  }

  Future<void> _loadUsageData(
    DateTime startDate,
    DateTime endDate, {
    bool notifyListenersIfNeeded = true,
  }) async {
    final usageList = await _databaseService.getUsageForDateRange(startDate, endDate);
    _todayUsage = usageList;

    // Calculate total time
    int totalSeconds = 0;
    for (final usage in usageList) {
      totalSeconds += usage.usageSeconds;
    }
    _totalSecondsToday = totalSeconds;

    // Aggregate by process
    final Map<String, int> processUsage = {};
    for (final usage in usageList) {
      final normalizedName = _normalizeProcessToken(usage.processName);
      if (normalizedName.isEmpty) {
        continue;
      }
      processUsage[normalizedName] =
          (processUsage[normalizedName] ?? 0) + usage.usageSeconds;
    }

    // Convert to aggregated list
    _aggregatedUsage = processUsage.entries.map((entry) {
      final percentage = totalSeconds > 0 
          ? (entry.value / totalSeconds) * 100 
          : 0.0;
      
      return AggregatedAppUsage(
        processName: entry.key,
        displayName: _formatProcessName(entry.key),
        totalSeconds: entry.value,
        percentage: percentage,
      );
    }).toList();

    // Sort by usage
    _sortAggregatedUsage();

    if (notifyListenersIfNeeded) {
      notifyListeners();
    }
  }

  Future<void> loadDailyUsage([int days = 7]) async {
    _dailyUsageWindowDays = days;
    _dailyUsage = await _databaseService.getDailyUsage(days);
    notifyListeners();
  }

  Future<void> refreshData() async {
    await Future.wait([
      loadDataForDays(_selectedDays),
      loadDailyUsage(_dailyUsageWindowDays),
    ]);
  }

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    loadDataForDays(1);
    notifyListeners();
  }

  String _formatProcessName(String processName) {
    // Convert process names to more readable format
    // e.g., "chrome" -> "Chrome", "Code" -> "VS Code"
    final displayNames = {
      'chrome': 'Google Chrome',
      'firefox': 'Firefox',
      'msedge': 'Microsoft Edge',
      'Code': 'VS Code',
      'WindowsTerminal': 'Terminal',
      'explorer': 'File Explorer',
      'Spotify': 'Spotify',
      'Discord': 'Discord',
      'slack': 'Slack',
      'Teams': 'Microsoft Teams',
      'OUTLOOK': 'Outlook',
      'WINWORD': 'Word',
      'EXCEL': 'Excel',
      'POWERPNT': 'PowerPoint',
      'notepad': 'Notepad',
      'Notion': 'Notion',
      'figma': 'Figma',
    };

    // Check for known apps (case insensitive)
    for (final entry in displayNames.entries) {
      if (processName.toLowerCase() == entry.key.toLowerCase()) {
        return entry.value;
      }
    }

    // Default: capitalize first letter
    if (processName.isEmpty) return processName;
    return processName[0].toUpperCase() + processName.substring(1);
  }

  @override
  void dispose() {
    _processTracker.dispose();
    super.dispose();
  }
}
