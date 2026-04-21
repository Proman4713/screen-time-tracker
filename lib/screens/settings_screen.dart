import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../providers/screen_time_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../services/app_icon_service.dart';
import '../services/installed_apps_service.dart';
import '../services/data_sync_service.dart';
import '../services/database_service.dart';
import '../services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import '../widgets/app_icon_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final List<Color> _accentColors = [
    Colors.blue,
    Colors.teal,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.magenta,
    Colors.purple,
    Colors.grey,
  ];

  Future<PackageInfo>? _packageInfoFuture;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page Header
                Text(
                  'Settings',
                  style: theme.typography.title?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Customize your Screen Time experience',
                  style: theme.typography.body?.copyWith(
                    color: isLight ? Colors.grey[130] : Colors.grey[100],
                  ),
                ),
                const SizedBox(height: 32),

                // Appearance Section
                _SectionHeader(title: 'Appearance', isLight: isLight),
                const SizedBox(height: 12),
                _SettingsCard(
                  isLight: isLight,
                  children: [
                    Consumer<ThemeProvider>(
                      builder: (context, themeProvider, child) {
                        return Column(
                          children: [
                            _SettingsRow(
                              icon: FluentIcons.light,
                              title: 'Theme',
                              subtitle: 'Choose light or dark mode',
                              isLight: isLight,
                              child: ComboBox<ThemeMode>(
                                value: themeProvider.themeMode,
                                items: const [
                                  ComboBoxItem(
                                    value: ThemeMode.system,
                                    child: Text('System default'),
                                  ),
                                  ComboBoxItem(
                                    value: ThemeMode.light,
                                    child: Text('Light'),
                                  ),
                                  ComboBoxItem(
                                    value: ThemeMode.dark,
                                    child: Text('Dark'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    themeProvider.setThemeMode(value);
                                  }
                                },
                              ),
                            ),
                            _Divider(isLight: isLight),
                            _SettingsRow(
                              icon: FluentIcons.color,
                              title: 'Use Windows accent color',
                              subtitle: 'Sync with your system personalization',
                              isLight: isLight,
                              child: ToggleSwitch(
                                checked: themeProvider.useSystemAccentColor,
                                onChanged: (value) =>
                                    themeProvider.setUseSystemAccentColor(value),
                              ),
                            ),
                            if (!themeProvider.useSystemAccentColor) ...[
                              _Divider(isLight: isLight),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Custom accent color',
                                      style: theme.typography.body,
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 40,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _accentColors.length,
                                        separatorBuilder: (context, index) =>
                                            const SizedBox(width: 8),
                                        itemBuilder: (context, index) {
                                          final color = _accentColors[index];
                                          final isSelected =
                                              themeProvider.customAccentColor.value ==
                                                  color.value;
                                          return GestureDetector(
                                            onTap: () =>
                                                themeProvider.setCustomAccentColor(color),
                                            child: Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: color,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? (isLight
                                                          ? Colors.black
                                                          : Colors.white)
                                                      : Colors.transparent,
                                                  width: 2,
                                                ),
                                              ),
                                              child: isSelected
                                                  ? Icon(
                                                      FluentIcons.check_mark,
                                                      size: 14,
                                                      color: color.computeLuminance() > 0.5
                                                          ? Colors.black
                                                          : Colors.white,
                                                    )
                                                  : null,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // General Section
                _SectionHeader(title: 'General', isLight: isLight),
                const SizedBox(height: 12),
                _SettingsCard(
                  isLight: isLight,
                  children: [
                    _SettingsRow(
                      icon: FluentIcons.power_button,
                      title: 'Start with Windows',
                      subtitle: 'Launch automatically when you sign in',
                      isLight: isLight,
                      child: ToggleSwitch(
                        checked: settings.startWithWindows,
                        onChanged: (value) =>
                            settings.setStartWithWindows(value),
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.system,
                      title: 'Minimize to tray',
                      subtitle: 'Keep running in the background when closed',
                      isLight: isLight,
                      child: ToggleSwitch(
                        checked: settings.minimizeToTray,
                        onChanged: (value) => settings.setMinimizeToTray(value),
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.ringer,
                      title: 'Notifications',
                      subtitle: 'Show daily usage summary notifications',
                      isLight: isLight,
                      child: ToggleSwitch(
                        checked: settings.showNotifications,
                        onChanged: (value) =>
                            settings.setShowNotifications(value),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Goals Section
                _SectionHeader(title: 'Goals & Reminders', isLight: isLight),
                const SizedBox(height: 12),
                _SettingsCard(
                  isLight: isLight,
                  children: [
                    _SettingsRow(
                      icon: FluentIcons.bullseye_target,
                      title: 'Daily screen time goal',
                      subtitle: settings.enableDailyGoal
                          ? 'Limit: ${settings.dailyGoalHours} hours per day'
                          : 'Set a daily usage limit',
                      isLight: isLight,
                      child: ToggleSwitch(
                        checked: settings.enableDailyGoal,
                        onChanged: (value) =>
                            settings.setEnableDailyGoal(value),
                      ),
                    ),
                    if (settings.enableDailyGoal) ...[
                      _Divider(isLight: isLight),
                      _SettingsRow(
                        icon: FluentIcons.clock,
                        title: 'Goal limit',
                        subtitle: 'Maximum hours per day',
                        isLight: isLight,
                        child: ComboBox<int>(
                          value: settings.dailyGoalHours,
                          items: [1, 2, 3, 4, 5, 6, 8, 10, 12]
                              .map(
                                (hours) => ComboBoxItem(
                                  value: hours,
                                  child: Text('$hours hours'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              settings.setDailyGoalHours(value);
                            }
                          },
                        ),
                      ),
                    ],
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.coffee_script,
                      title: 'Break reminders',
                      subtitle: settings.enableBreakReminders
                          ? 'Remind every ${settings.breakReminderInterval} minutes'
                          : 'Get reminded to take breaks',
                      isLight: isLight,
                      child: ToggleSwitch(
                        checked: settings.enableBreakReminders,
                        onChanged: (value) =>
                            settings.setEnableBreakReminders(value),
                      ),
                    ),
                    if (settings.enableBreakReminders) ...[
                      _Divider(isLight: isLight),
                      _SettingsRow(
                        icon: FluentIcons.timer,
                        title: 'Break interval',
                        subtitle: 'Time between break reminders',
                        isLight: isLight,
                        child: ComboBox<int>(
                          value: settings.breakReminderInterval,
                          items: [15, 20, 30, 45, 60, 90, 120]
                              .map(
                                (mins) => ComboBoxItem(
                                  value: mins,
                                  child: Text('$mins min'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              settings.setBreakReminderInterval(value);
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 28),

                // Tracking Section
                _SectionHeader(title: 'Tracking', isLight: isLight),
                const SizedBox(height: 12),
                Consumer<ScreenTimeProvider>(
                  builder: (context, provider, child) {
                    return _SettingsCard(
                      isLight: isLight,
                      children: [
                        _SettingsRow(
                          icon: provider.isTracking
                              ? FluentIcons.play_solid
                              : FluentIcons.pause,
                          title: 'Tracking status',
                          subtitle: provider.isTracking
                              ? 'Currently monitoring active windows'
                              : 'Tracking is paused',
                          isLight: isLight,
                          child: FilledButton(
                            onPressed: () => provider.toggleTracking(),
                            child: Text(
                              provider.isTracking ? 'Pause' : 'Resume',
                            ),
                          ),
                        ),
                        _Divider(isLight: isLight),
                        _SettingsRow(
                          icon: FluentIcons.timer,
                          title: 'Idle timeout',
                          subtitle:
                              'Pause tracking after ${settings.idleTimeout} min of inactivity',
                          isLight: isLight,
                          child: ComboBox<int>(
                            value: settings.idleTimeout,
                            items: [1, 2, 5, 10, 15, 30]
                                .map(
                                  (mins) => ComboBoxItem(
                                    value: mins,
                                    child: Text('$mins min'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                settings.setIdleTimeout(value);
                              }
                            },
                          ),
                        ),
                        _Divider(isLight: isLight),
                        _SettingsRow(
                          icon: FluentIcons.processing,
                          title: 'Tracking precision',
                          subtitle:
                              'Check active window every ${settings.trackingInterval} second(s)',
                          isLight: isLight,
                          child: ComboBox<int>(
                            value: settings.trackingInterval,
                            items: [1, 2, 5, 10]
                                .map(
                                  (sec) => ComboBoxItem(
                                    value: sec,
                                    child: Text('$sec sec'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                settings.setTrackingInterval(value);
                              }
                            },
                          ),
                        ),
                        _Divider(isLight: isLight),
                        _SettingsRow(
                          icon: FluentIcons.blocked2,
                          title: 'Ignored applications',
                          subtitle:
                              '${settings.ignoredApps.length} apps excluded from tracking',
                          isLight: isLight,
                          child: Button(
                            child: const Text('Manage'),
                            onPressed: () =>
                                _showIgnoredAppsDialog(context, settings),
                          ),
                        ),
                        _Divider(isLight: isLight),
                        _SettingsRow(
                          icon: FluentIcons.favorite_star,
                          title: 'Productive applications',
                          subtitle:
                              '${settings.productiveApps.length} apps counted towards focus score',
                          isLight: isLight,
                          child: Button(
                            child: const Text('Manage'),
                            onPressed: () =>
                                _showProductiveAppsDialog(context, settings),
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 28),

                // Privacy Section
                _SectionHeader(title: 'Privacy', isLight: isLight),
                const SizedBox(height: 12),
                _SettingsCard(
                  isLight: isLight,
                  children: [
                    _SettingsRow(
                      icon: FluentIcons.hide3,
                      title: 'Blur app names',
                      subtitle: 'Hide application names in the UI',
                      isLight: isLight,
                      child: ToggleSwitch(
                        checked: settings.blurAppNames,
                        onChanged: (value) => settings.setBlurAppNames(value),
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.lock,
                      title: 'Pause on lock',
                      subtitle: 'Stop tracking when screen is locked',
                      isLight: isLight,
                      child: ToggleSwitch(
                        checked: settings.pauseOnLock,
                        onChanged: (value) => settings.setPauseOnLock(value),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Data Section
                _SectionHeader(title: 'Data', isLight: isLight),
                const SizedBox(height: 12),
                _SettingsCard(
                  isLight: isLight,
                  children: [
                    _SettingsRow(
                      icon: FluentIcons.database,
                      title: 'Data retention',
                      subtitle:
                          'Keep usage data for ${settings.dataRetentionDays} days',
                      isLight: isLight,
                      child: ComboBox<int>(
                        value: settings.dataRetentionDays,
                        items: [7, 14, 30, 60, 90, 365]
                            .map(
                              (days) => ComboBoxItem(
                                value: days,
                                child: Text('$days days'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            settings.setDataRetentionDays(value);
                          }
                        },
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.download,
                      title: 'Export data',
                      subtitle: 'Save your usage history to a file',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Export'),
                        onPressed: () => _showExportDialog(context),
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.upload,
                      title: 'Import data',
                      subtitle: 'Restore from a backup file',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Import'),
                        onPressed: () => _showImportDialog(context),
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.delete,
                      title: 'Clear all data',
                      subtitle: 'Permanently delete all tracking history',
                      isLight: isLight,
                      child: Button(
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.isHovered) {
                              return Colors.red.withOpacity(0.15);
                            }
                            return Colors.red.withOpacity(0.08);
                          }),
                        ),
                        child: Text(
                          'Clear',
                          style: TextStyle(color: Colors.red.lighter),
                        ),
                        onPressed: () => _showClearDataDialog(context),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // About Section
                _SectionHeader(title: 'About', isLight: isLight),
                const SizedBox(height: 12),
                _SettingsCard(
                  isLight: isLight,
                  children: [
                    FutureBuilder<PackageInfo>(
                      future: _packageInfoFuture ??= PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final version = snapshot.data?.version ?? '1.0.0';
                        return _SettingsRow(
                          icon: FluentIcons.info,
                          title: 'Screen Time',
                          subtitle: 'Version $version',
                          isLight: isLight,
                          child: Button(
                            child: const Text('Check for updates'),
                            onPressed: () => _showUpdateCheckDialog(context),
                          ),
                        );
                      },
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.reset,
                      title: 'Reset settings',
                      subtitle: 'Restore all settings to defaults',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Reset'),
                        onPressed: () =>
                            _showResetSettingsDialog(context, settings),
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.document,
                      title: 'Keyboard shortcuts',
                      subtitle: 'View available shortcuts',
                      isLight: isLight,
                      child: Button(
                        child: const Text('View'),
                        onPressed: () => _showShortcutsDialog(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Feedback Section
                _SectionHeader(title: 'Feedback & Support', isLight: isLight),
                const SizedBox(height: 12),
                _SettingsCard(
                  isLight: isLight,
                  children: [
                    _SettingsRow(
                      icon: FluentIcons.send,
                      title: 'Telegram',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Chat'),
                        onPressed: () async {
                          final url = Uri.parse('https://t.me/arifulislamkhan');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.globe,
                      title: 'X (Twitter)',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Follow'),
                        onPressed: () async {
                          final url = Uri.parse('https://x.com/andrenoari');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.mail,
                      title: 'Email',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Email'),
                        onPressed: () async {
                          final url = Uri.parse('mailto:contact@ariful.work');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Support the Developer Section
                _SectionHeader(title: 'Support the Developer', isLight: isLight),
                const SizedBox(height: 12),
                _SettingsCard(
                  isLight: isLight,
                  children: [
                    _SettingsRow(
                      icon: FluentIcons.payment_card,
                      title: 'UPI',
                      subtitle: 'Support via UPI',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Support'),
                        onPressed: () => _showUPIDialog(context),
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.payment_card,
                      title: 'PayPal',
                      subtitle: 'Support via PayPal',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Support'),
                        onPressed: () async {
                          final url = Uri.parse('https://paypal.me/arifulik');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.coffee,
                      title: 'Ko-fi',
                      subtitle: 'Buy me a ko-fi',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Support'),
                        onPressed: () async {
                          final url = Uri.parse('https://ko-fi.com/andrenoari');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                      ),
                    ),
                    _Divider(isLight: isLight),
                    _SettingsRow(
                      icon: FluentIcons.coffee_script,
                      title: 'Buy Me a Coffee',
                      subtitle: 'Support my work',
                      isLight: isLight,
                      child: Button(
                        child: const Text('Support'),
                        onPressed: () async {
                          final url = Uri.parse('https://buymeacoffee.com/andrenoari');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showIgnoredAppsDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final controller = TextEditingController();
    bool isLoadingApps = true;
    bool hasStartedLoading = false;
    bool forceRefreshInstalledApps = false;
    List<InstalledApp> installedApps = [];
    final Map<String, String> installedExecutablePaths = {};
    InstalledApp? selectedApp;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (!hasStartedLoading) {
            hasStartedLoading = true;
            () async {
              try {
                final apps = await InstalledAppsService.getInstalledApps(
                  forceRefresh: forceRefreshInstalledApps,
                );

                if (!mounted) {
                  return;
                }

                setDialogState(() {
                  installedApps = apps;
                  isLoadingApps = false;
                  forceRefreshInstalledApps = false;
                  installedExecutablePaths
                    ..clear()
                    ..addEntries(
                      apps.where((app) => app.executablePath != null).map(
                            (app) => MapEntry(
                              app.processName.toLowerCase(),
                              app.executablePath!,
                            ),
                          ),
                    );

                  if (selectedApp != null &&
                      !apps.any(
                        (app) =>
                            app.processName.toLowerCase() ==
                            selectedApp!.processName.toLowerCase(),
                      )) {
                    selectedApp = null;
                  }
                });

                // Warm icon cache for the first visible results so logos appear quickly.
                unawaited(() async {
                  final prefetched = apps
                      .where((app) => app.executablePath != null)
                      .take(20)
                      .toList();
                  for (final app in prefetched) {
                    await AppIconService.instance.getIconPath(
                      app.processName,
                      executablePath: app.executablePath,
                    );
                  }
                }());
              } catch (e) {
                if (!mounted) {
                  return;
                }

                setDialogState(() {
                  installedApps = [];
                  isLoadingApps = false;
                  forceRefreshInstalledApps = false;
                  installedExecutablePaths.clear();
                  selectedApp = null;
                });
              }
            }();
          }

          return ContentDialog(
            title: const Text('Ignored Applications'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Apps in this list will not be tracked.'),
                  const SizedBox(height: 16),

                  // Installed Apps Dropdown
                  Text(
                    'Select from installed apps:',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: isLoadingApps
                            ? const ProgressRing(strokeWidth: 2)
                            : ComboBox<InstalledApp>(
                                isExpanded: true,
                                placeholder: Text(
                                  installedApps.isEmpty
                                      ? 'No installed apps found'
                                      : 'Select an installed app',
                                ),
                                value: selectedApp,
                                items: installedApps.map((app) {
                                  return ComboBoxItem<InstalledApp>(
                                    value: app,
                                    child: Row(
                                      children: [
                                        AppIconWidget(
                                          processName: app.processName,
                                          executablePath: app.executablePath,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${app.displayName} (${app.processName})',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (app) {
                                  if (app != null) {
                                    setDialogState(() => selectedApp = app);
                                  }
                                },
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(FluentIcons.refresh),
                        onPressed: isLoadingApps
                            ? null
                            : () {
                                setDialogState(() {
                                  isLoadingApps = true;
                                  hasStartedLoading = false;
                                  forceRefreshInstalledApps = true;
                                  selectedApp = null;
                                });
                              },
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        child: const Text('Add'),
                        onPressed: selectedApp == null
                            ? null
                            : () async {
                                await AppIconService.instance.getIconPath(
                                  selectedApp!.processName,
                                  executablePath: selectedApp!.executablePath,
                                );
                                await settings.addIgnoredApp(
                                  selectedApp!.processName,
                                );
                                setDialogState(() => selectedApp = null);
                              },
                      ),
                    ],
                  ),

                  if (!isLoadingApps && installedApps.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No installed apps found. Click refresh or add manually below.',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                    ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Manual input fallback
                  Text(
                    'Or type exact process name manually:',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextBox(
                          controller: controller,
                          placeholder: 'e.g., notepad.exe',
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        child: const Text('Add'),
                        onPressed: () async {
                          if (controller.text.isNotEmpty) {
                            await settings.addIgnoredApp(controller.text);
                            controller.clear();
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Active List
                  if (settings.ignoredApps.isEmpty)
                    const Text('No apps ignored yet.')
                  else
                    SizedBox(
                      height: 150,
                      child: ListView.builder(
                        itemCount: settings.ignoredApps.length,
                        itemBuilder: (context, index) {
                          final app = settings.ignoredApps[index];
                          return ListTile(
                            leading: AppIconWidget(
                              processName: app,
                              executablePath:
                                  installedExecutablePaths[app.toLowerCase()],
                              size: 20,
                            ),
                            title: Text(app),
                            trailing: IconButton(
                              icon: const Icon(FluentIcons.delete),
                              onPressed: () async {
                                await settings.removeIgnoredApp(app);
                                setDialogState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                child: const Text('Done'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showProductiveAppsDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final controller = TextEditingController();
    bool isLoadingApps = true;
    bool hasStartedLoading = false;
    bool forceRefreshInstalledApps = false;
    List<InstalledApp> installedApps = [];
    final Map<String, String> installedExecutablePaths = {};
    InstalledApp? selectedApp;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (!hasStartedLoading) {
            hasStartedLoading = true;
            () async {
              try {
                final apps = await InstalledAppsService.getInstalledApps(
                  forceRefresh: forceRefreshInstalledApps,
                );

                if (!mounted) {
                  return;
                }

                setDialogState(() {
                  installedApps = apps;
                  isLoadingApps = false;
                  forceRefreshInstalledApps = false;
                  installedExecutablePaths
                    ..clear()
                    ..addEntries(
                      apps.where((app) => app.executablePath != null).map(
                            (app) => MapEntry(
                              app.processName.toLowerCase(),
                              app.executablePath!,
                            ),
                          ),
                    );

                  if (selectedApp != null &&
                      !apps.any(
                        (app) =>
                            app.processName.toLowerCase() ==
                            selectedApp!.processName.toLowerCase(),
                      )) {
                    selectedApp = null;
                  }
                });

                // Warm icon cache for the first visible results so logos appear quickly.
                unawaited(() async {
                  final prefetched = apps
                      .where((app) => app.executablePath != null)
                      .take(20)
                      .toList();
                  for (final app in prefetched) {
                    await AppIconService.instance.getIconPath(
                      app.processName,
                      executablePath: app.executablePath,
                    );
                  }
                }());
              } catch (e) {
                if (!mounted) {
                  return;
                }

                setDialogState(() {
                  installedApps = [];
                  isLoadingApps = false;
                  forceRefreshInstalledApps = false;
                  installedExecutablePaths.clear();
                  selectedApp = null;
                });
              }
            }();
          }

          return ContentDialog(
            title: const Text('Productive Applications'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Apps in this list will contribute to your Focus Score.',
                  ),
                  const SizedBox(height: 16),

                  // Installed Apps Dropdown
                  Text(
                    'Select from installed apps:',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: isLoadingApps
                            ? const ProgressRing(strokeWidth: 2)
                            : ComboBox<InstalledApp>(
                                isExpanded: true,
                                placeholder: Text(
                                  installedApps.isEmpty
                                      ? 'No installed apps found'
                                      : 'Select an installed app',
                                ),
                                value: selectedApp,
                                items: installedApps.map((app) {
                                  return ComboBoxItem<InstalledApp>(
                                    value: app,
                                    child: Row(
                                      children: [
                                        AppIconWidget(
                                          processName: app.processName,
                                          executablePath: app.executablePath,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${app.displayName} (${app.processName})',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (app) {
                                  if (app != null) {
                                    setDialogState(() => selectedApp = app);
                                  }
                                },
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(FluentIcons.refresh),
                        onPressed: isLoadingApps
                            ? null
                            : () {
                                setDialogState(() {
                                  isLoadingApps = true;
                                  hasStartedLoading = false;
                                  forceRefreshInstalledApps = true;
                                  selectedApp = null;
                                });
                              },
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        child: const Text('Add'),
                        onPressed: selectedApp == null
                            ? null
                            : () async {
                                await AppIconService.instance.getIconPath(
                                  selectedApp!.processName,
                                  executablePath: selectedApp!.executablePath,
                                );
                                await settings.addProductiveApp(
                                  selectedApp!.processName,
                                );
                                setDialogState(() => selectedApp = null);
                              },
                      ),
                    ],
                  ),

                  if (!isLoadingApps && installedApps.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No installed apps found. Click refresh or add manually below.',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                    ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Manual input fallback
                  Text(
                    'Or type exact process name manually:',
                    style: FluentTheme.of(context).typography.caption,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextBox(
                          controller: controller,
                          placeholder: 'e.g., Code.exe',
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        child: const Text('Add'),
                        onPressed: () async {
                          if (controller.text.isNotEmpty) {
                            await settings.addProductiveApp(controller.text);
                            controller.clear();
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Active List
                  if (settings.productiveApps.isEmpty)
                    const Text('No productive apps added yet.')
                  else
                    SizedBox(
                      height: 150,
                      child: ListView.builder(
                        itemCount: settings.productiveApps.length,
                        itemBuilder: (context, index) {
                          final app = settings.productiveApps[index];
                          return ListTile(
                            leading: AppIconWidget(
                              processName: app,
                              executablePath:
                                  installedExecutablePaths[app.toLowerCase()],
                              size: 20,
                              fallbackIcon: FluentIcons.favorite_star,
                            ),
                            title: Text(app),
                            trailing: IconButton(
                              icon: const Icon(FluentIcons.delete),
                              onPressed: () async {
                                await settings.removeProductiveApp(app);
                                setDialogState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                child: const Text('Done'),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showExportDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Export Data'),
        content: const Text(
          'Choose a format to export your screen time history.',
        ),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          Button(
            child: const Text('CSV'),
            onPressed: () async {
              Navigator.pop(context);
              final success = await DataSyncService().exportData(ExportFormat.csv);
              if (success && context.mounted) {
                _showExportSuccessMessage(context, 'CSV');
              }
            },
          ),
          FilledButton(
            child: const Text('JSON'),
            onPressed: () async {
              Navigator.pop(context);
              final success = await DataSyncService().exportData(ExportFormat.json);
              if (success && context.mounted) {
                _showExportSuccessMessage(context, 'JSON');
              }
            },
          ),
        ],
      ),
    );
  }

  void _showExportSuccessMessage(BuildContext context, String format) async {
    await displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('Export Complete'),
        content: Text('Your tracking backup data has been successfully exported as $format.'),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
    );
  }

  void _showImportDialog(
    BuildContext context, {
    String? initialFilePath,
    ImportMode initialMode = ImportMode.merge,
  }) async {
    String modeLabel(ImportMode mode) {
      switch (mode) {
        case ImportMode.merge:
          return 'Merge safely';
        case ImportMode.replace:
          return 'Replace existing data';
      }
    }

    String modeDescription(ImportMode mode) {
      switch (mode) {
        case ImportMode.merge:
          return 'Skips duplicates and keeps the highest totals for matching records.';
        case ImportMode.replace:
          return 'Clears current usage history before importing file data.';
      }
    }

    final parentContext = context;
    String? selectedFilePath = initialFilePath;
    ImportMode selectedMode = initialMode;
    ImportPreview? preview;
    bool isBusy = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasFile = selectedFilePath?.isNotEmpty ?? false;
          final contentWidth = (MediaQuery.sizeOf(context).width - 80)
              .clamp(320.0, 560.0)
              .toDouble();

          return ContentDialog(
            title: const Text('Import Data'),
            content: SizedBox(
              width: contentWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose a backup file, preview what will change, then import in Merge or Replace mode.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasFile ? 'Selected file: $selectedFilePath' : 'No file selected',
                      style: FluentTheme.of(context).typography.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    InfoLabel(
                      label: 'Import mode',
                      child: ComboBox<ImportMode>(
                        value: selectedMode,
                        isExpanded: true,
                        items: [
                          ComboBoxItem(
                            value: ImportMode.merge,
                            child: Text(
                              modeLabel(ImportMode.merge),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ComboBoxItem(
                            value: ImportMode.replace,
                            child: Text(
                              modeLabel(ImportMode.replace),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: isBusy
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() => selectedMode = value);
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      modeDescription(selectedMode),
                      style: FluentTheme.of(context).typography.caption,
                    ),
                    if (preview != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: FluentTheme.of(context).brightness == Brightness.light
                              ? const Color(0xFFF5F5F5)
                              : const Color(0xFF2D2D2D),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Preview', style: FluentTheme.of(context).typography.bodyStrong),
                            const SizedBox(height: 8),
                            Text('Rows in file: ${preview!.totalRows}'),
                            Text('Valid rows: ${preview!.validRows}'),
                            Text('Invalid rows skipped: ${preview!.invalidRows}'),
                            Text('Consolidated records: ${preview!.consolidatedRecords}'),
                            Text('New records: ${preview!.newRecords}'),
                            Text('Duplicates skipped in merge: ${preview!.duplicateRecords}'),
                            Text('Conflicts to resolve: ${preview!.conflictingRecords}'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              Button(
                child: const Text('Cancel'),
                onPressed: isBusy ? null : () => Navigator.pop(dialogContext),
              ),
              Button(
                child: const Text('Browse'),
                onPressed: isBusy
                    ? null
                    : () async {
                        final modeBeforePick = selectedMode;
                        final previousFilePath = selectedFilePath;
                        Navigator.pop(dialogContext);

                        final filePath = await DataSyncService().pickImportFilePath();
                        if (!mounted) {
                          return;
                        }

                        _showImportDialog(
                          parentContext,
                          initialFilePath: filePath ?? previousFilePath,
                          initialMode: modeBeforePick,
                        );
                      },
              ),
              Button(
                child: isBusy
                    ? const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
                    : const Text('Preview'),
                onPressed: (!hasFile || isBusy)
                    ? null
                    : () async {
                        final activeFilePath = selectedFilePath;
                        if (activeFilePath == null || activeFilePath.isEmpty) {
                          return;
                        }

                        setDialogState(() => isBusy = true);
                        final previewResult = await DataSyncService()
                            .previewImportFile(activeFilePath);
                        if (!parentContext.mounted) {
                          return;
                        }
                        setDialogState(() {
                          preview = previewResult;
                          isBusy = false;
                        });
                      },
              ),
              FilledButton(
                child: const Text('Import'),
                onPressed: (!hasFile || isBusy)
                    ? null
                    : () async {
                        final activeFilePath = selectedFilePath;
                        if (activeFilePath == null || activeFilePath.isEmpty) {
                          return;
                        }

                        if (selectedMode == ImportMode.replace) {
                          final confirmed = await showDialog<bool>(
                                context: dialogContext,
                                builder: (context) => ContentDialog(
                                  title: const Text('Confirm Replace Import'),
                                  content: const Text(
                                    'Replace mode will delete all current usage history before importing this file. Continue?',
                                  ),
                                  actions: [
                                    Button(
                                      child: const Text('Cancel'),
                                      onPressed: () => Navigator.pop(context, false),
                                    ),
                                    FilledButton(
                                      child: const Text('Replace Data'),
                                      onPressed: () => Navigator.pop(context, true),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;
                          if (!confirmed) {
                            return;
                          }
                        }

                        setDialogState(() => isBusy = true);
                        final result = await DataSyncService().importData(
                          activeFilePath,
                          mode: selectedMode,
                        );
                        if (!parentContext.mounted) {
                          return;
                        }

                        Navigator.pop(dialogContext);

                        if (result.success) {
                          await parentContext
                              .read<ScreenTimeProvider>()
                              .refreshData();
                          if (!parentContext.mounted) {
                            return;
                          }
                          await displayInfoBar(
                            parentContext,
                            builder: (context, close) => InfoBar(
                              title: const Text('Import Complete'),
                              content: Text(result.message),
                              severity: InfoBarSeverity.success,
                              onClose: close,
                            ),
                          );
                        } else {
                          await displayInfoBar(
                            parentContext,
                            builder: (context, close) => InfoBar(
                              title: const Text('Import Failed'),
                              content: Text(result.message),
                              severity: InfoBarSeverity.error,
                              onClose: close,
                            ),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showClearDataDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will permanently delete all your screen time data. This action cannot be undone.',
        ),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.red),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      // Actually clear the database
      await DatabaseService.instance.clearAllUsage();
      
      if (mounted) {
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('Data cleared'),
            content: const Text('All usage data has been permanently deleted.'),
            severity: InfoBarSeverity.warning,
            onClose: close,
          ),
        );
      }
    }
  }

  void _showUpdateCheckDialog(BuildContext context) async {
    // 1. Show checking dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ContentDialog(
        title: const Text('Checking for Updates'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(height: 16),
            ProgressRing(),
            SizedBox(height: 16),
            Text('Contacting update server...'),
          ],
        ),
      ),
    );

    try {
      // 2. Perform real update check
      final updateService = UpdateService();
      final updateInfo = await updateService.checkForUpdates();

      if (mounted) {
        Navigator.pop(context); // Close checking dialog

        if (updateInfo.isUpdateAvailable) {
          // 3. Show Update Available Dialog
          await showDialog(
            context: context,
            builder: (context) => ContentDialog(
              title: const Text('Update Available'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('A new version (v${updateInfo.latestVersion}) is available.'),
                  if (updateInfo.releaseNotes != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Release Notes:',
                      style: FluentTheme.of(context).typography.bodyStrong,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      updateInfo.releaseNotes!,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
              actions: [
                Button(
                  child: const Text('Later'),
                  onPressed: () => Navigator.pop(context),
                ),
                FilledButton(
                  onPressed: updateInfo.downloadUrl == null
                      ? null
                      : () async {
                          final url = Uri.parse(updateInfo.downloadUrl!);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url);
                          }
                          if (context.mounted) Navigator.pop(context);
                        },
                  child: const Text('Download & Install'),
                ),
              ],
            ),
          );
        } else {
          // 4. Show "Up to date" InfoBar
          await displayInfoBar(
            context,
            builder: (context, close) => InfoBar(
              title: const Text('You\'re up to date!'),
              content: const Text('Screen Time v1.0.0 is the latest version.'),
              severity: InfoBarSeverity.success,
              onClose: close,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close checking dialog
        await displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('Check Failed'),
            content: Text('Could not reach the update server. Please check your internet connection.'),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    }
  }

  void _showResetSettingsDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'This will restore all settings to their default values. Your usage data will not be affected.',
        ),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await settings.resetToDefaults();
      await displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Settings reset'),
          content: const Text('All settings have been restored to defaults.'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    }
  }

  void _showShortcutsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Keyboard Shortcuts'),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _ShortcutRow(
                shortcut: 'Ctrl + H',
                description: 'Go to Dashboard',
              ),
              _ShortcutRow(
                shortcut: 'Ctrl + S',
                description: 'Go to Statistics',
              ),
              _ShortcutRow(shortcut: 'Ctrl + ,', description: 'Open Settings'),
              _ShortcutRow(
                shortcut: 'Ctrl + P',
                description: 'Pause/Resume tracking',
              ),
              _ShortcutRow(shortcut: 'Ctrl + R', description: 'Refresh data'),
              _ShortcutRow(
                shortcut: 'Ctrl + Q',
                description: 'Quit application',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showUPIDialog(BuildContext context) async {
    const upiId = 'arifulislamkhan@upi';
    const upiName = 'Ariful Islam Khan';
    final upiUrl = 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(upiName)}&cu=INR';
    final qrUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(upiUrl)}';

    await showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Support via UPI'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Scan the QR code to support using any UPI app'),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.network(
                qrUrl,
                width: 200,
                height: 200,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    width: 200,
                    height: 200,
                    child: Center(child: ProgressRing()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => SizedBox(
                  width: 200,
                  height: 200,
                  child: Center(
                    child: Icon(FluentIcons.error_badge, color: Colors.red),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SelectableText(
                  upiId,
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(FluentIcons.copy, size: 14),
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: upiId));
                    displayInfoBar(
                      context,
                      builder: (context, close) => InfoBar(
                        title: const Text('Copied'),
                        content: const Text('UPI ID copied to clipboard'),
                        severity: InfoBarSeverity.success,
                        onClose: close,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String shortcut;
  final String description;

  const _ShortcutRow({required this.shortcut, required this.description});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isLight ? Colors.grey[40] : Colors.grey[150],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              shortcut,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(description),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isLight;

  const _SectionHeader({required this.title, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Text(
      title,
      style: theme.typography.bodyStrong?.copyWith(
        color: isLight ? Colors.grey[160] : Colors.grey[80],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final bool isLight;

  const _SettingsCard({required this.children, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF9F9F9) : const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLight ? const Color(0xFFE5E5E5) : const Color(0xFF3D3D3D),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final bool isLight;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: theme.accentColor, size: 16),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.typography.body),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: theme.typography.caption?.copyWith(
                      color: isLight ? Colors.grey[130] : Colors.grey[100],
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isLight;

  const _Divider({required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: isLight ? const Color(0xFFE5E5E5) : const Color(0xFF3D3D3D),
    );
  }
}
