import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'dart:io';
import 'dart:convert';
import '../models/app_block.dart';

class SettingsProvider with ChangeNotifier {
  late SharedPreferences _prefs;
  bool _isInitialized = false;

  String _normalizeProcessName(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.endsWith('.exe')) {
      return normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  // General Settings
  bool _startWithWindows = false;
  bool _minimizeToTray = true;
  bool _showNotifications = true;

  // Tracking Settings
  int _idleTimeout = 5; // minutes
  int _trackingInterval = 1; // seconds
  List<String> _ignoredApps = [];
  List<String> _productiveApps = [];

  // Goals Settings
  bool _enableDailyGoal = false;
  int _dailyGoalHours = 4;
  bool _enableBreakReminders = false;
  int _breakReminderInterval = 60; // minutes

  // Privacy Settings
  bool _blurAppNames = false;
  bool _pauseOnLock = true;

  // Data Settings
  int _dataRetentionDays = 30;

  // Blocking Settings
  List<AppBlock> _blockRules = [];

  // Getters
  bool get isInitialized => _isInitialized;
  bool get startWithWindows => _startWithWindows;
  bool get minimizeToTray => _minimizeToTray;
  bool get showNotifications => _showNotifications;
  int get idleTimeout => _idleTimeout;
  int get trackingInterval => _trackingInterval;
  List<String> get ignoredApps => List.unmodifiable(_ignoredApps);
  List<String> get productiveApps => List.unmodifiable(_productiveApps);
  bool get enableDailyGoal => _enableDailyGoal;
  int get dailyGoalHours => _dailyGoalHours;
  bool get enableBreakReminders => _enableBreakReminders;
  int get breakReminderInterval => _breakReminderInterval;
  bool get blurAppNames => _blurAppNames;
  bool get pauseOnLock => _pauseOnLock;
  int get dataRetentionDays => _dataRetentionDays;
  List<AppBlock> get blockRules => List.unmodifiable(_blockRules);

  Future<void> initialize() async {
    if (_isInitialized) return;

    _prefs = await SharedPreferences.getInstance();

    // Load all settings from SharedPreferences
    _startWithWindows = _prefs.getBool('startWithWindows') ?? false;
    _minimizeToTray = _prefs.getBool('minimizeToTray') ?? true;
    _showNotifications = _prefs.getBool('showNotifications') ?? true;
    _idleTimeout = _prefs.getInt('idleTimeout') ?? 5;
    _trackingInterval = _prefs.getInt('trackingInterval') ?? 1;
    _ignoredApps = (_prefs.getStringList('ignoredApps') ?? [])
      .map(_normalizeProcessName)
      .where((name) => name.isNotEmpty)
      .toSet()
      .toList();
    _productiveApps = _prefs.getStringList('productiveApps') ?? [];
    _enableDailyGoal = _prefs.getBool('enableDailyGoal') ?? false;
    _dailyGoalHours = _prefs.getInt('dailyGoalHours') ?? 4;
    _enableBreakReminders = _prefs.getBool('enableBreakReminders') ?? false;
    _breakReminderInterval = _prefs.getInt('breakReminderInterval') ?? 60;
    _blurAppNames = _prefs.getBool('blurAppNames') ?? false;
    _pauseOnLock = _prefs.getBool('pauseOnLock') ?? true;
    _dataRetentionDays = _prefs.getInt('dataRetentionDays') ?? 30;

    // Load block rules
    final rulesJson = _prefs.getStringList('blockRules') ?? [];
    _blockRules = rulesJson
        .map((json) => AppBlock.fromJson(jsonDecode(json)))
        .map(
          (rule) => rule.copyWith(
            processName: _normalizeProcessName(rule.processName),
          ),
        )
        .toList();

    // Setup launch at startup
    if (Platform.isWindows) {
      launchAtStartup.setup(
        appName: 'Screen Time Tracker',
        appPath: Platform.resolvedExecutable,
      );
      
      // Sync the actual state
      final isEnabled = await launchAtStartup.isEnabled();
      if (isEnabled != _startWithWindows) {
        _startWithWindows = isEnabled;
        await _prefs.setBool('startWithWindows', isEnabled);
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  // General Settings Setters
  Future<void> setStartWithWindows(bool value) async {
    if (_startWithWindows == value) return;
    
    _startWithWindows = value;
    await _prefs.setBool('startWithWindows', value);

    if (Platform.isWindows) {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    }

    notifyListeners();
  }

  Future<void> setMinimizeToTray(bool value) async {
    if (_minimizeToTray == value) return;
    
    _minimizeToTray = value;
    await _prefs.setBool('minimizeToTray', value);
    notifyListeners();
  }

  Future<void> setShowNotifications(bool value) async {
    if (_showNotifications == value) return;
    
    _showNotifications = value;
    await _prefs.setBool('showNotifications', value);
    notifyListeners();
  }

  // Tracking Settings Setters
  Future<void> setIdleTimeout(int value) async {
    if (_idleTimeout == value) return;
    
    _idleTimeout = value;
    await _prefs.setInt('idleTimeout', value);
    notifyListeners();
  }

  Future<void> setTrackingInterval(int value) async {
    if (_trackingInterval == value) return;
    
    _trackingInterval = value;
    await _prefs.setInt('trackingInterval', value);
    notifyListeners();
  }

  Future<void> addIgnoredApp(String appName) async {
    final normalizedName = _normalizeProcessName(appName);
    if (normalizedName.isEmpty) return;

    if (_ignoredApps.any((app) => _normalizeProcessName(app) == normalizedName)) {
      return;
    }
    
    _ignoredApps.add(normalizedName);
    await _prefs.setStringList('ignoredApps', _ignoredApps);
    notifyListeners();
  }

  Future<void> removeIgnoredApp(String appName) async {
    final normalizedName = _normalizeProcessName(appName);
    final before = _ignoredApps.length;
    _ignoredApps.removeWhere((app) => _normalizeProcessName(app) == normalizedName);
    if (_ignoredApps.length == before) return;

    await _prefs.setStringList('ignoredApps', _ignoredApps);
    notifyListeners();
  }

  bool isAppIgnored(String appName) {
    final normalizedName = _normalizeProcessName(appName);
    return _ignoredApps.any((ignored) => 
      normalizedName == _normalizeProcessName(ignored) ||
      normalizedName.contains(_normalizeProcessName(ignored))
    );
  }

  Future<void> addProductiveApp(String appName) async {
    if (_productiveApps.contains(appName)) return;
    
    _productiveApps.add(appName);
    await _prefs.setStringList('productiveApps', _productiveApps);
    notifyListeners();
  }

  Future<void> removeProductiveApp(String appName) async {
    if (!_productiveApps.contains(appName)) return;
    
    _productiveApps.remove(appName);
    await _prefs.setStringList('productiveApps', _productiveApps);
    notifyListeners();
  }

  // Goals Settings Setters
  Future<void> setEnableDailyGoal(bool value) async {
    if (_enableDailyGoal == value) return;
    
    _enableDailyGoal = value;
    await _prefs.setBool('enableDailyGoal', value);
    notifyListeners();
  }

  Future<void> setDailyGoalHours(int value) async {
    if (_dailyGoalHours == value) return;
    
    _dailyGoalHours = value;
    await _prefs.setInt('dailyGoalHours', value);
    notifyListeners();
  }

  Future<void> setEnableBreakReminders(bool value) async {
    if (_enableBreakReminders == value) return;
    
    _enableBreakReminders = value;
    await _prefs.setBool('enableBreakReminders', value);
    notifyListeners();
  }

  Future<void> setBreakReminderInterval(int value) async {
    if (_breakReminderInterval == value) return;
    
    _breakReminderInterval = value;
    await _prefs.setInt('breakReminderInterval', value);
    notifyListeners();
  }

  // Privacy Settings Setters
  Future<void> setBlurAppNames(bool value) async {
    if (_blurAppNames == value) return;
    
    _blurAppNames = value;
    await _prefs.setBool('blurAppNames', value);
    notifyListeners();
  }

  Future<void> setPauseOnLock(bool value) async {
    if (_pauseOnLock == value) return;
    
    _pauseOnLock = value;
    await _prefs.setBool('pauseOnLock', value);
    notifyListeners();
  }

  // Data Settings Setters
  Future<void> setDataRetentionDays(int value) async {
    if (_dataRetentionDays == value) return;
    
    _dataRetentionDays = value;
    await _prefs.setInt('dataRetentionDays', value);
    notifyListeners();
  }

  // Blocking Settings Setters
  Future<void> addBlockRule(AppBlock rule) async {
    final normalizedName = _normalizeProcessName(rule.processName);
    final normalizedRule = rule.copyWith(processName: normalizedName);
    final existingIndex = _blockRules.indexWhere(
      (r) => _normalizeProcessName(r.processName) == normalizedName,
    );

    if (existingIndex != -1) {
      _blockRules[existingIndex] = normalizedRule;
    } else {
      _blockRules.add(normalizedRule);
    }
    await _saveBlockRules();
    notifyListeners();
  }

  Future<void> removeBlockRule(String processName) async {
    final normalizedName = _normalizeProcessName(processName);
    _blockRules.removeWhere(
      (r) => _normalizeProcessName(r.processName) == normalizedName,
    );
    await _saveBlockRules();
    notifyListeners();
  }

  Future<void> updateBlockRule(AppBlock updatedRule) async {
    final normalizedName = _normalizeProcessName(updatedRule.processName);
    final normalizedRule = updatedRule.copyWith(processName: normalizedName);
    final index = _blockRules.indexWhere(
      (r) => _normalizeProcessName(r.processName) == normalizedName,
    );
    if (index != -1) {
      _blockRules[index] = normalizedRule;
      await _saveBlockRules();
      notifyListeners();
    }
  }

  Future<void> _saveBlockRules() async {
    final rulesJson = _blockRules
        .map((rule) => jsonEncode(rule.toJson()))
        .toList();
    await _prefs.setStringList('blockRules', rulesJson);
  }

  // Reset all settings to defaults
  Future<void> resetToDefaults() async {
    _startWithWindows = false;
    _minimizeToTray = true;
    _showNotifications = true;
    _idleTimeout = 5;
    _trackingInterval = 1;
    _ignoredApps = [];
    _productiveApps = [];
    _enableDailyGoal = false;
    _dailyGoalHours = 4;
    _enableBreakReminders = false;
    _breakReminderInterval = 60;
    _blurAppNames = false;
    _pauseOnLock = true;
    _dataRetentionDays = 30;
    _blockRules = [];

    await _prefs.clear();
    
    if (Platform.isWindows) {
      await launchAtStartup.disable();
    }

    notifyListeners();
  }
}
