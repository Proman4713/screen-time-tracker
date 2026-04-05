import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:provider/provider.dart';
import '../models/app_block.dart';
import '../providers/settings_provider.dart';
import '../providers/screen_time_provider.dart';
import '../services/installed_apps_service.dart';
import '../widgets/app_icon_widget.dart';

class BlockingScreen extends StatefulWidget {
  const BlockingScreen({super.key});

  @override
  State<BlockingScreen> createState() => _BlockingScreenState();
}

class _BlockingScreenState extends State<BlockingScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final settings = context.watch<SettingsProvider>();

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('App Blocking'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('Add Block'),
              onPressed: () => _showAddBlockDialog(context),
            ),
          ],
        ),
      ),
      content: settings.blockRules.isEmpty
          ? _buildEmptyState(theme)
          : _buildBlockList(settings, theme, isLight),
    );
  }

  Widget _buildEmptyState(FluentThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.shield_alert, size: 64, color: theme.accentColor),
          const SizedBox(height: 16),
          Text(
            'No apps blocked',
            style: theme.typography.subtitle,
          ),
          const SizedBox(height: 8),
          const Text('Add an app to limit usage or schedule blocks.'),
        ],
      ),
    );
  }

  Widget _buildBlockList(SettingsProvider settings, FluentThemeData theme, bool isLight) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: settings.blockRules.length,
      itemBuilder: (context, index) {
        final rule = settings.blockRules[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: AppIconWidget(
              processName: rule.processName,
              size: 24,
              fallbackIcon: FluentIcons.blocked2,
            ),
            title: Text(rule.processName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rule.dailyLimitSeconds != null)
                  Text('Daily Limit: ${rule.dailyLimitSeconds! ~/ 60} minutes'),
                if (rule.blockStartMinutes != null && rule.blockEndMinutes != null)
                  Text('Scheduled Block: ${_formatMinutes(rule.blockStartMinutes!)} - ${_formatMinutes(rule.blockEndMinutes!)}'),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToggleSwitch(
                  checked: rule.isEnabled,
                  onChanged: (value) {
                    settings.updateBlockRule(rule.copyWith(isEnabled: value));
                    context.read<ScreenTimeProvider>().setBlockRules(settings.blockRules);
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(FluentIcons.edit),
                  onPressed: () => _showAddBlockDialog(context, existingRule: rule),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.delete),
                  onPressed: () {
                    settings.removeBlockRule(rule.processName);
                    context.read<ScreenTimeProvider>().setBlockRules(settings.blockRules);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddBlockDialog(BuildContext context, {AppBlock? existingRule}) async {
    final nameController = TextEditingController(text: existingRule?.processName);
    int? limitMinutes = existingRule?.dailyLimitSeconds != null ? existingRule!.dailyLimitSeconds! ~/ 60 : null;
    TimeOfDay? start = existingRule?.blockStartMinutes != null 
        ? TimeOfDay(hour: existingRule!.blockStartMinutes! ~/ 60, minute: existingRule!.blockStartMinutes! % 60)
        : null;
    TimeOfDay? end = existingRule?.blockEndMinutes != null
        ? TimeOfDay(hour: existingRule!.blockEndMinutes! ~/ 60, minute: existingRule!.blockEndMinutes! % 60)
        : null;
    bool isLoadingApps = true;
    bool hasStartedLoading = false;
    bool forceRefreshInstalledApps = false;
    List<InstalledApp> installedApps = [];
    InstalledApp? selectedApp;

    await showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(existingRule == null ? 'Add Block Rule' : 'Edit Block Rule'),
        content: StatefulBuilder(
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

                    if (selectedApp != null &&
                        !apps.any(
                          (app) =>
                              app.processName.toLowerCase() ==
                              selectedApp!.processName.toLowerCase(),
                        )) {
                      selectedApp = null;
                    }

                    if (existingRule != null && selectedApp == null) {
                      for (final app in apps) {
                        if (app.processName.toLowerCase() ==
                            existingRule.processName.toLowerCase()) {
                          selectedApp = app;
                          break;
                        }
                      }
                    }
                  });
                } catch (e) {
                  if (!mounted) {
                    return;
                  }

                  setDialogState(() {
                    installedApps = [];
                    isLoadingApps = false;
                    forceRefreshInstalledApps = false;
                    selectedApp = null;
                  });
                }
              }();
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                                  setDialogState(() {
                                    selectedApp = app;
                                    nameController.text = app.processName;
                                  });
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
                              });
                            },
                    ),
                  ],
                ),

                if (!isLoadingApps && installedApps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No installed apps found. You can still type process name manually.',
                      style: FluentTheme.of(context).typography.caption,
                    ),
                  ),

                const SizedBox(height: 12),
                InfoLabel(
                  label: 'App Process Name',
                  child: TextBox(
                    controller: nameController,
                    placeholder: 'Process name (e.g., chrome.exe)',
                  ),
                ),
                const SizedBox(height: 16),
                Expander(
                  header: const Text('Daily Usage Limit'),
                  content: Row(
                    children: [
                      const Text('Limit: '),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: NumberBox<int>(
                          value: limitMinutes,
                          onChanged: (v) => setDialogState(() => limitMinutes = v),
                          placeholder: 'Minutes',
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('minutes'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expander(
                  header: const Text('Scheduled Block'),
                  content: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 40, child: Text('Start: ')),
                          Expanded(
                            child: TimePicker(
                              selected: DateTime(2022, 1, 1, start?.hour ?? 0, start?.minute ?? 0),
                              onChanged: (v) => setDialogState(() => start = TimeOfDay.fromDateTime(v)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(width: 40, child: Text('End: ')),
                          Expanded(
                            child: TimePicker(
                              selected: DateTime(2022, 1, 1, end?.hour ?? 0, end?.minute ?? 0),
                              onChanged: (v) => setDialogState(() => end = TimeOfDay.fromDateTime(v)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
        ),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: Text(existingRule == null ? 'Add' : 'Save'),
            onPressed: () async {
              final processName = nameController.text.trim();
              if (processName.isEmpty) return;

              final newRule = AppBlock(
                processName: processName,
                dailyLimitSeconds: limitMinutes != null ? limitMinutes! * 60 : null,
                blockStartMinutes: start != null ? start!.hour * 60 + start!.minute : null,
                blockEndMinutes: end != null ? end!.hour * 60 + end!.minute : null,
              );

              final settings = context.read<SettingsProvider>();
              if (existingRule == null) {
                await settings.addBlockRule(newRule);
              } else if (existingRule.processName.toLowerCase() ==
                  newRule.processName.toLowerCase()) {
                await settings.updateBlockRule(newRule);
              } else {
                await settings.removeBlockRule(existingRule.processName);
                await settings.addBlockRule(newRule);
              }
              
              context.read<ScreenTimeProvider>().setBlockRules(settings.blockRules);
              if (!context.mounted) {
                return;
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $ampm';
  }
}
