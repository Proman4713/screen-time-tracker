import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter/gestures.dart';
import '../providers/screen_time_provider.dart';
import '../providers/settings_provider.dart';

// Helper to obscure app names
String _obscureAppName(String name, bool shouldBlur) {
  if (!shouldBlur) return name;
  if (name.length <= 2) return '••';
  return name[0] + '•' * (name.length - 2) + name[name.length - 1];
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header with greeting
            _buildHeader(context, theme, isLight),
            const SizedBox(height: 24),

            // Hero Stats Card
            _buildHeroCard(context, theme, isLight),
            const SizedBox(height: 20),

            // Quick Stats Row
            _buildQuickStatsRow(context, theme, isLight),
            const SizedBox(height: 24),

            // Main Content Row - Chart + Top Apps
            LayoutBuilder(
              builder: (context, constraints) {
                final useStackedCards = constraints.maxWidth < 1050;

                if (useStackedCards) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildUsageChart(context, theme, isLight),
                      const SizedBox(height: 16),
                      _buildTopAppsCard(context, theme, isLight),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildUsageChart(context, theme, isLight),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _buildTopAppsCard(context, theme, isLight),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // Recent Activity + Usage Trend Row
            LayoutBuilder(
              builder: (context, constraints) {
                final useStackedCards = constraints.maxWidth < 900;

                if (useStackedCards) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRecentActivityCard(context, theme, isLight),
                      const SizedBox(height: 16),
                      _buildQuickActionsCard(context, theme, isLight),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildRecentActivityCard(context, theme, isLight),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildQuickActionsCard(context, theme, isLight),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, FluentThemeData theme, bool isLight) {
    final hour = DateTime.now().hour;
    String greeting;
    IconData greetingIcon;
    
    if (hour < 12) {
      greeting = 'Good morning';
      greetingIcon = FluentIcons.sunny;
    } else if (hour < 17) {
      greeting = 'Good afternoon';
      greetingIcon = FluentIcons.brightness;
    } else {
      greeting = 'Good evening';
      greetingIcon = FluentIcons.clear_night;
    }

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              greetingIcon,
              size: 18,
              color: theme.accentColor,
            ),
            const SizedBox(width: 8),
            Text(
              '$greeting!',
              style: theme.typography.title?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('EEEE, MMMM d').format(DateTime.now()),
          style: theme.typography.body?.copyWith(
            color: isLight ? Colors.grey[130] : Colors.grey[100],
          ),
        ),
      ],
    );

    final refreshButton = Tooltip(
      message: 'Refresh data (Ctrl+R)',
      child: FilledButton(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(FluentIcons.refresh, size: 14),
            SizedBox(width: 8),
            Text('Refresh'),
          ],
        ),
        onPressed: () => context.read<ScreenTimeProvider>().refreshData(),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 960;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              SizedBox(
                width: constraints.maxWidth,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildTimePeriodSelector(context, theme, isLight),
                ),
              ),
              const SizedBox(height: 8),
              refreshButton,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            titleBlock,
            Row(
              children: [
                _buildTimePeriodSelector(context, theme, isLight),
                const SizedBox(width: 8),
                refreshButton,
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimePeriodSelector(BuildContext context, FluentThemeData theme, bool isLight) {
    return Consumer<ScreenTimeProvider>(
      builder: (context, provider, child) {
        return Container(
          decoration: BoxDecoration(
            color: isLight
                ? const Color(0xFFF3F3F3)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isLight
                  ? const Color(0xFFE5E5E5)
                  : const Color(0xFF3D3D3D),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SegmentButton(
                label: 'Today',
                isSelected: provider.selectedDays == 1,
                onPressed: () => provider.loadDataForDays(1),
                isFirst: true,
                isLight: isLight,
              ),
              _SegmentButton(
                label: '7 Days',
                isSelected: provider.selectedDays == 7,
                onPressed: () => provider.loadDataForDays(7),
                isLight: isLight,
              ),
              _SegmentButton(
                label: '14 Days',
                isSelected: provider.selectedDays == 14,
                onPressed: () => provider.loadDataForDays(14),
                isLight: isLight,
              ),
              _SegmentButton(
                label: '30 Days',
                isSelected: provider.selectedDays == 30,
                onPressed: () => provider.loadDataForDays(30),
                isLast: true,
                isLight: isLight,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroCard(BuildContext context, FluentThemeData theme, bool isLight) {
    return Consumer<ScreenTimeProvider>(
      builder: (context, provider, child) {
        final hours = provider.totalSecondsToday ~/ 3600;
        final minutes = (provider.totalSecondsToday % 3600) ~/ 60;
        final seconds = provider.totalSecondsToday % 60;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.accentColor,
                theme.accentColor.lighter,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: theme.accentColor.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: provider.isTracking 
                                      ? Colors.green.lighter 
                                      : Colors.orange.lighter,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                provider.isTracking ? 'TRACKING' : 'PAUSED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        FilledButton(
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.isHovered) {
                                return Colors.white.withValues(alpha: 0.35);
                              }
                              return Colors.white.withValues(alpha: 0.2);
                            }),
                            foregroundColor: WidgetStateProperty.all(Colors.white),
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          onPressed: () => provider.toggleTracking(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                provider.isTracking 
                                    ? FluentIcons.pause 
                                    : FluentIcons.play,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                provider.isTracking ? 'Pause' : 'Resume',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      provider.selectedDays == 1 
                          ? 'Today\'s Screen Time' 
                          : 'Total Screen Time',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$hours',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(
                            'h',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$minutes',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 4),
                          child: Text(
                            'm',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        if (provider.selectedDays == 1) ...[
                          const SizedBox(width: 8),
                          Text(
                            '$seconds',
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, left: 4),
                            child: Text(
                              's',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (provider.currentApp.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              FluentIcons.app_icon_default,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Currently: ${provider.currentApp}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickStatsRow(BuildContext context, FluentThemeData theme, bool isLight) {
    return Consumer2<ScreenTimeProvider, SettingsProvider>(
      builder: (context, provider, settings, child) {
        final appCount = provider.aggregatedUsage.length;
        final topApp = provider.aggregatedUsage.isNotEmpty 
            ? provider.aggregatedUsage.first 
            : null;
        
        // Calculate average daily usage
        final avgMinutes = provider.selectedDays > 0 
            ? (provider.totalSecondsToday / 60 / provider.selectedDays).round()
            : 0;

        // Apply blur to most used app name if setting is enabled
        final topAppName = topApp != null
            ? (settings.blurAppNames 
                ? _obscureAppName(topApp.displayName, true) 
                : topApp.displayName)
            : '—';

        final cards = <Widget>[
          _QuickStatCard(
            icon: FluentIcons.app_icon_default,
            title: 'Apps Used',
            value: '$appCount',
            color: Colors.teal,
            isLight: isLight,
          ),
          _QuickStatCard(
            icon: FluentIcons.trophy2,
            title: 'Most Used',
            value: topAppName,
            color: Colors.orange,
            isLight: isLight,
            smallText: true,
          ),
          _QuickStatCard(
            icon: FluentIcons.calendar,
            title: 'Daily Avg',
            value: '${avgMinutes}m',
            color: Colors.purple,
            isLight: isLight,
          ),
          _QuickStatCard(
            icon: FluentIcons.clock,
            title: 'Top App Time',
            value: topApp?.formattedTime ?? '—',
            color: Colors.magenta,
            isLight: isLight,
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 980;

            if (!isCompact) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[2]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[3]),
                  ],
                ),
              );
            }

            final useSingleColumn = constraints.maxWidth < 560;
            final cardWidth = useSingleColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map((card) => SizedBox(width: cardWidth, child: card))
                  .toList(),
            );
          },
        );
      },
    );
  }

  Widget _buildUsageChart(BuildContext context, FluentThemeData theme, bool isLight) {
    return _UsageChartCard(isLight: isLight);
  }

  Widget _buildTopAppsCard(BuildContext context, FluentThemeData theme, bool isLight) {
    return Consumer2<ScreenTimeProvider, SettingsProvider>(
      builder: (context, provider, settings, child) {
        // Sync settings with provider post-frame to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          provider.setIgnoredApps(settings.ignoredApps);
          provider.setProductiveApps(settings.productiveApps);
          provider.setIdleTimeout(settings.idleTimeout);
          
          provider.configureNotifications(
            enableDailyGoal: settings.enableDailyGoal,
            dailyGoalHours: settings.dailyGoalHours,
            enableBreakReminders: settings.enableBreakReminders,
            breakReminderIntervalMinutes: settings.breakReminderInterval,
          );

          provider.setPauseOnLock(settings.pauseOnLock);
          provider.setShowNotifications(settings.showNotifications);
          provider.setDataRetentionDays(settings.dataRetentionDays);

          if (provider.trackingInterval != settings.trackingInterval) {
            provider.setTrackingInterval(settings.trackingInterval);
          }
        });
        
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isLight
                ? const Color(0xFFF9F9F9)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isLight
                  ? const Color(0xFFE5E5E5)
                  : const Color(0xFF3D3D3D),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Top Applications',
                    style: theme.typography.bodyStrong,
                  ),
                  IconButton(
                    icon: Icon(
                      provider.isAscending ? FluentIcons.sort_up : FluentIcons.sort_down,
                      size: 14,
                      color: isLight ? Colors.grey[100] : Colors.grey[120],
                    ),
                    onPressed: () => provider.toggleSortOrder(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (provider.aggregatedUsage.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          FluentIcons.app_icon_default,
                          size: 32,
                          color: isLight ? Colors.grey[90] : Colors.grey[100],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No apps tracked yet',
                          style: theme.typography.caption?.copyWith(
                            color: isLight ? Colors.grey[130] : Colors.grey[100],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...provider.aggregatedUsage.take(5).toList().asMap().entries.map((entry) {
                  final index = entry.key;
                  final app = entry.value;
                  return _AppRow(
                    rank: index + 1,
                    app: app,
                    theme: theme,
                    isLight: isLight,
                    blurName: settings.blurAppNames,
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentActivityCard(BuildContext context, FluentThemeData theme, bool isLight) {
    return Consumer<ScreenTimeProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isLight
                ? const Color(0xFFF9F9F9)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isLight
                  ? const Color(0xFFE5E5E5)
                  : const Color(0xFF3D3D3D),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Session Summary',
                    style: theme.typography.bodyStrong,
                  ),
                  Icon(
                    FluentIcons.history,
                    size: 14,
                    color: isLight ? Colors.grey[100] : Colors.grey[120],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SummaryRow(
                icon: FluentIcons.timer,
                label: 'Session started',
                value: provider.isTracking 
                    ? DateFormat('h:mm a').format(DateTime.now().subtract(
                        Duration(seconds: provider.totalSecondsToday % 3600)))
                    : '—',
                isLight: isLight,
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                icon: FluentIcons.app_icon_default,
                label: 'Apps this session',
                value: '${provider.aggregatedUsage.length}',
                isLight: isLight,
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                icon: FluentIcons.red_eye,
                label: 'Focus score',
                value: provider.totalSecondsToday > 0 
                    ? '${provider.focusScore.toStringAsFixed(0)}%'
                    : '—',
                valueColor: Colors.green,
                isLight: isLight,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActionsCard(BuildContext context, FluentThemeData theme, bool isLight) {
    return Consumer<ScreenTimeProvider>(
      builder: (context, provider, child) {
        final now = DateTime.now();
        final todayKey = DateFormat('yyyy-MM-dd').format(now);
        final yesterdayKey = DateFormat(
          'yyyy-MM-dd',
        ).format(now.subtract(const Duration(days: 1)));

        final usageByDate = <String, int>{};
        for (final row in provider.dailyUsage) {
          final dateKey = row['date'] as String?;
          if (dateKey == null || dateKey.isEmpty) {
            continue;
          }
          usageByDate[dateKey] = (row['total_seconds'] as int?) ?? 0;
        }

        // Use live tracker total for today when it is ahead of persisted daily rollup.
        int todaySeconds = usageByDate[todayKey] ?? 0;
        if (provider.liveTodayTotalSeconds > todaySeconds) {
          todaySeconds = provider.liveTodayTotalSeconds;
        }

        final todayHours = todaySeconds ~/ 3600;
        final todayMinutes = (todaySeconds % 3600) ~/ 60;

        final yesterdaySeconds = usageByDate[yesterdayKey] ?? 0;

        final yesterdayHours = yesterdaySeconds ~/ 3600;
        final yesterdayMinutes = (yesterdaySeconds % 3600) ~/ 60;

        // Calculate change percentage
        final changePercent = yesterdaySeconds > 0
            ? ((todaySeconds - yesterdaySeconds) / yesterdaySeconds * 100).round()
            : (todaySeconds > 0 ? 100 : 0);
        final isIncrease = todaySeconds > yesterdaySeconds;

        // Max for progress bar
        final maxSeconds = todaySeconds > yesterdaySeconds ? todaySeconds : yesterdaySeconds;
        
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isLight
                ? const Color(0xFFF9F9F9)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isLight
                  ? const Color(0xFFE5E5E5)
                  : const Color(0xFF3D3D3D),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Usage Trend',
                    style: theme.typography.bodyStrong,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (isIncrease ? Colors.orange : Colors.green)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isIncrease ? FluentIcons.up : FluentIcons.down,
                          size: 10,
                          color: isIncrease ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${changePercent.abs()}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isIncrease ? Colors.orange : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Today row
              _CompactTrendRow(
                label: 'Today',
                value: '${todayHours}h ${todayMinutes}m',
                progress: maxSeconds > 0 ? todaySeconds / maxSeconds : 0,
                color: theme.accentColor,
                isLight: isLight,
              ),
              const SizedBox(height: 12),
              // Yesterday row
              _CompactTrendRow(
                label: 'Yesterday',
                value: '${yesterdayHours}h ${yesterdayMinutes}m',
                progress: maxSeconds > 0 ? yesterdaySeconds / maxSeconds : 0,
                color: Colors.grey[100],
                isLight: isLight,
              ),
              const SizedBox(height: 12),
              // Insight row - inline
              Row(
                children: [
                  Icon(
                    isIncrease ? FluentIcons.warning : FluentIcons.completed,
                    size: 14,
                    color: isIncrease ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isIncrease
                        ? 'Up ${changePercent.abs()}% from yesterday'
                        : 'Down ${changePercent.abs()}% from yesterday',
                    style: theme.typography.caption?.copyWith(
                      color: isIncrease ? Colors.orange : Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final bool isFirst;
  final bool isLast;
  final bool isLight;

  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.isFirst = false,
    this.isLast = false,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.accentColor : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(7) : Radius.zero,
            right: isLast ? const Radius.circular(7) : Radius.zero,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : (isLight ? Colors.grey[130] : Colors.grey[100]),
          ),
        ),
      ),
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final bool isLight;
  final bool smallText;

  const _QuickStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.isLight,
    this.smallText = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFF9F9F9)
            : const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLight
              ? const Color(0xFFE5E5E5)
              : const Color(0xFF3D3D3D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: smallText ? 14 : 18,
              fontWeight: FontWeight.w600,
              color: theme.typography.body?.color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: theme.typography.caption?.copyWith(
              color: isLight ? Colors.grey[130] : Colors.grey[100],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  final int rank;
  final dynamic app;
  final FluentThemeData theme;
  final bool isLight;
  final bool blurName;

  const _AppRow({
    required this.rank,
    required this.app,
    required this.theme,
    required this.isLight,
    this.blurName = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = blurName 
        ? _obscureAppName(app.displayName, true) 
        : app.displayName;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _getRankColor(rank).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _getRankColor(rank),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: theme.typography.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ProgressBar(value: app.percentage),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            app.formattedTime,
            style: theme.typography.caption?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.orange;
      case 2:
        return Colors.grey[120];
      case 3:
        return Colors.orange.dark;
      default:
        return Colors.grey[100];
    }
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLight;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.accentColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.typography.caption?.copyWith(
              color: isLight ? Colors.grey[130] : Colors.grey[100],
            ),
          ),
        ),
        Text(
          value,
          style: theme.typography.body?.copyWith(
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _CompactTrendRow extends StatelessWidget {
  final String label;
  final String value;
  final double progress;
  final Color color;
  final bool isLight;

  const _CompactTrendRow({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: theme.typography.caption?.copyWith(
              color: isLight ? Colors.grey[130] : Colors.grey[100],
            ),
          ),
        ),
        Text(
          value,
          style: theme.typography.body?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}


// ─── Enhanced Usage Chart ───────────────────────────────────────────────────

class _UsageChartCard extends StatefulWidget {
  final bool isLight;

  const _UsageChartCard({required this.isLight});

  @override
  State<_UsageChartCard> createState() => _UsageChartCardState();
}

class _UsageChartCardState extends State<_UsageChartCard> {
  int _touchedIndex = -1;

  static const _chartColors = <Color>[
    Color(0xFF0078D4), // Blue
    Color(0xFF00B7C3), // Teal
    Color(0xFF107C10), // Green
    Color(0xFFFF8C00), // Amber
    Color(0xFFE81123), // Red
    Color(0xFFB4009E), // Magenta
    Color(0xFF5C2D91), // Purple
  ];

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isLight = widget.isLight;

    return Consumer2<ScreenTimeProvider, SettingsProvider>(
      builder: (context, provider, settings, child) {
        final usage = provider.aggregatedUsage;
        final displayUsage = _getDisplayUsage(usage);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isLight
                ? const Color(0xFFF9F9F9)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isLight
                  ? const Color(0xFFE5E5E5)
                  : const Color(0xFF3D3D3D),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Usage Distribution',
                    style: theme.typography.bodyStrong,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${displayUsage.length} apps',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.accentColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Chart content
              if (displayUsage.isEmpty)
                _buildEmptyState(theme, isLight)
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useStackedLayout = constraints.maxWidth < 700;

                    final pieSection = Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            pieTouchData: PieTouchData(
                              touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                setState(() {
                                  if (!event.isInterestedForInteractions ||
                                      pieTouchResponse == null ||
                                      pieTouchResponse.touchedSection == null) {
                                    _touchedIndex = -1;
                                    return;
                                  }
                                  _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                });
                              },
                            ),
                            borderData: FlBorderData(show: false),
                            sectionsSpace: 2,
                            centerSpaceRadius: 45,
                            sections: _buildSections(displayUsage, theme),
                          ),
                          swapAnimationDuration: const Duration(milliseconds: 400),
                          swapAnimationCurve: Curves.easeInOut,
                        ),
                        _buildCenterDisplay(displayUsage, provider, theme, isLight),
                      ],
                    );

                    final legendSection = Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          GestureBinding.instance.pointerSignalResolver.register(
                            event,
                            (event) {},
                          );
                        }
                      },
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildLegendItems(
                              displayUsage,
                              theme,
                              isLight,
                              blur: settings.blurAppNames,
                            ),
                          ),
                        ),
                      ),
                    );

                    if (useStackedLayout) {
                      return SizedBox(
                        height: 340,
                        child: Column(
                          children: [
                            Expanded(
                              flex: 3,
                              child: pieSection,
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              flex: 2,
                              child: legendSection,
                            ),
                          ],
                        ),
                      );
                    }

                    return SizedBox(
                      height: 200,
                      child: Row(
                        children: [
                          Expanded(child: pieSection),
                          const SizedBox(width: 20),
                          Expanded(child: legendSection),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Groups apps with <90 seconds into a single "Others" entry.
  List<_DisplayApp> _getDisplayUsage(List<dynamic> usage) {
    final mainApps = <_DisplayApp>[];
    int othersSeconds = 0;
    int totalSeconds = 0;

    for (final app in usage) {
      totalSeconds += app.totalSeconds as int;
      if (app.totalSeconds >= 90) {
        mainApps.add(_DisplayApp(
          displayName: app.displayName,
          totalSeconds: app.totalSeconds,
          percentage: app.percentage,
          formattedTime: app.formattedTime,
        ));
      } else {
        othersSeconds += app.totalSeconds as int;
      }
    }

    if (othersSeconds > 0 && totalSeconds > 0) {
      final othersPct = (othersSeconds / totalSeconds) * 100;
      final h = othersSeconds ~/ 3600;
      final m = (othersSeconds % 3600) ~/ 60;
      final s = othersSeconds % 60;
      String formatted;
      if (h > 0) {
        formatted = '${h}h ${m}m';
      } else if (m > 0) {
        formatted = '${m}m ${s}s';
      } else {
        formatted = '${s}s';
      }
      mainApps.add(_DisplayApp(
        displayName: 'Others',
        totalSeconds: othersSeconds,
        percentage: othersPct,
        formattedTime: formatted,
        isOthers: true,
      ));
    }

    return mainApps;
  }

  Widget _buildEmptyState(FluentThemeData theme, bool isLight) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.chart,
              size: 40,
              color: isLight ? Colors.grey[90] : Colors.grey[100],
            ),
            const SizedBox(height: 12),
            Text(
              'No data available',
              style: theme.typography.body?.copyWith(
                color: isLight ? Colors.grey[130] : Colors.grey[100],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start tracking to see your usage',
              style: theme.typography.caption?.copyWith(
                color: isLight ? Colors.grey[100] : Colors.grey[120],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForIndex(int i, List<_DisplayApp> usage) {
    if (usage[i].isOthers) return const Color(0xFF888888);
    return _chartColors[i % _chartColors.length];
  }

  Widget _buildCenterDisplay(
    List<_DisplayApp> usage,
    ScreenTimeProvider provider,
    FluentThemeData theme,
    bool isLight,
  ) {
    final isHovering = _touchedIndex >= 0 && _touchedIndex < usage.length;
    final seconds = isHovering
        ? usage[_touchedIndex].totalSeconds
        : provider.totalSecondsToday;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isHovering ? '${usage[_touchedIndex].percentage.toStringAsFixed(0)}%' : '${h}h ${m}m',
          style: theme.typography.bodyStrong?.copyWith(
            fontSize: 16,
            color: isHovering
                ? _colorForIndex(_touchedIndex, usage)
                : null,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          isHovering ? 'of total' : 'Total',
          style: theme.typography.caption?.copyWith(
            fontSize: 10,
            color: isLight ? Colors.grey[120] : Colors.grey[100],
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildSections(List<_DisplayApp> usage, FluentThemeData theme) {
    return List.generate(usage.length, (i) {
      final isTouched = i == _touchedIndex;
      final radius = isTouched ? 46.0 : 40.0;
      final opacity = _touchedIndex == -1 || isTouched ? 1.0 : 0.6;
      final color = _colorForIndex(i, usage);

      return PieChartSectionData(
        color: color.withValues(alpha: opacity),
        value: usage[i].totalSeconds.toDouble(),
        title: isTouched ? '${usage[i].percentage.toStringAsFixed(0)}%' : '',
        radius: radius,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      );
    });
  }

  List<Widget> _buildLegendItems(
    List<_DisplayApp> usage,
    FluentThemeData theme,
    bool isLight,
    {bool blur = false}
  ) {
    return [
      ...usage.asMap().entries.map((entry) {
        final i = entry.key;
        final app = entry.value;
        final isSelected = i == _touchedIndex;
        final color = _colorForIndex(i, usage);
        final displayName = (blur && !app.isOthers)
            ? _obscureAppName(app.displayName, true)
            : app.displayName;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _touchedIndex = i),
          onExit: (_) => setState(() => _touchedIndex = -1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isLight
                      ? theme.accentColor.withValues(alpha: 0.06)
                      : theme.accentColor.withValues(alpha: 0.08))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                // Left accent strip on hover
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 3,
                  height: isSelected ? 16 : 0,
                  decoration: BoxDecoration(
                    color: isSelected ? theme.accentColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: isSelected ? 8 : 0),
                // Color indicator
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: theme.typography.caption?.copyWith(
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isLight ? Colors.grey[130] : Colors.grey[100],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            app.formattedTime,
                            style: theme.typography.caption?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: isSelected ? theme.accentColor : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Progress bar
                      Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: isLight
                              ? const Color(0xFFE5E5E5)
                              : const Color(0xFF3D3D3D),
                          borderRadius: BorderRadius.circular(1),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (app.percentage / 100).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ];
  }
}

class _DisplayApp {
  final String displayName;
  final int totalSeconds;
  final double percentage;
  final String formattedTime;
  final bool isOthers;

  const _DisplayApp({
    required this.displayName,
    required this.totalSeconds,
    required this.percentage,
    required this.formattedTime,
    this.isOthers = false,
  });
}
