import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/screen_time_provider.dart';
import '../providers/settings_provider.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  int _selectedTimeRange = 7; // 7 days default

  static const List<int> _supportedRanges = <int>[7, 14, 30];

  int _normalizeRange(int days) {
    if (_supportedRanges.contains(days)) {
      return days;
    }
    if (days <= 7) {
      return 7;
    }
    if (days <= 14) {
      return 14;
    }
    return 30;
  }

  @override
  void initState() {
    super.initState();
    final provider = context.read<ScreenTimeProvider>();
    _selectedTimeRange = _normalizeRange(provider.selectedDays);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _applyTimeRange(_selectedTimeRange);
    });
  }

  Future<void> _applyTimeRange(int days, {bool force = false}) async {
    if (!mounted) {
      return;
    }

    final normalizedDays = _normalizeRange(days);
    final provider = context.read<ScreenTimeProvider>();

    final alreadyLoaded =
        _selectedTimeRange == normalizedDays &&
        provider.selectedDays == normalizedDays &&
        provider.dailyUsageWindowDays == normalizedDays;
    if (!force && alreadyLoaded) {
      return;
    }

    if (_selectedTimeRange != normalizedDays) {
      setState(() => _selectedTimeRange = normalizedDays);
    }

    await provider.loadDataForDays(normalizedDays);
    await provider.loadDailyUsage(normalizedDays);
  }

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
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Header
              _buildHeader(theme, isLight),
              const SizedBox(height: 24),

              // Quick Stats Row
              _buildQuickStats(theme, isLight),
              const SizedBox(height: 24),

              // Daily Usage Chart + Top Apps Row
              LayoutBuilder(
                builder: (context, constraints) {
                  final useStackedCards = constraints.maxWidth < 1050;

                  if (useStackedCards) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDailyChart(theme, isLight),
                        const SizedBox(height: 16),
                        _buildTopAppsCard(theme, isLight),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Daily Usage Chart
                      Expanded(
                        flex: 3,
                        child: _buildDailyChart(theme, isLight),
                      ),
                      const SizedBox(width: 16),
                      // Top Apps this week
                      Expanded(
                        flex: 2,
                        child: _buildTopAppsCard(theme, isLight),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Usage Insights + Weekly Comparison Row
              LayoutBuilder(
                builder: (context, constraints) {
                  final useStackedCards = constraints.maxWidth < 900;

                  if (useStackedCards) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildUsagePatternCard(theme, isLight),
                        const SizedBox(height: 16),
                        _buildTrendsCard(theme, isLight),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Usage Insights
                      Expanded(
                        child: _buildUsagePatternCard(theme, isLight),
                      ),
                      const SizedBox(width: 16),
                      // Weekly Comparison
                      Expanded(
                        child: _buildTrendsCard(theme, isLight),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(FluentThemeData theme, bool isLight) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Statistics',
          style: theme.typography.title?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Detailed insights into your screen time',
          style: theme.typography.body?.copyWith(
            color: isLight ? Colors.grey[130] : Colors.grey[100],
          ),
        ),
      ],
    );

    final timeRangeSelector = Container(
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
          _TimeRangeButton(
            label: '7D',
            isSelected: _selectedTimeRange == 7,
            onPressed: () => _applyTimeRange(7),
            isFirst: true,
            isLight: isLight,
          ),
          _TimeRangeButton(
            label: '14D',
            isSelected: _selectedTimeRange == 14,
            onPressed: () => _applyTimeRange(14),
            isLight: isLight,
          ),
          _TimeRangeButton(
            label: '30D',
            isSelected: _selectedTimeRange == 30,
            onPressed: () => _applyTimeRange(30),
            isLast: true,
            isLight: isLight,
          ),
        ],
      ),
    );

    final refreshButton = FilledButton(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(FluentIcons.refresh, size: 14),
          SizedBox(width: 8),
          Text('Refresh'),
        ],
      ),
      onPressed: () {
        _applyTimeRange(_selectedTimeRange, force: true);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  timeRangeSelector,
                  refreshButton,
                ],
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            titleBlock,
            Row(
              children: [
                timeRangeSelector,
                const SizedBox(width: 12),
                refreshButton,
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickStats(FluentThemeData theme, bool isLight) {
    return Consumer<ScreenTimeProvider>(
      builder: (context, provider, child) {
        final dailyData = provider.dailyUsage;
        final totalSeconds = provider.currentPeriodTotalSeconds;
        final previousPeriodSeconds = provider.previousPeriodTotalSeconds;

        int maxSeconds = 0;
        int minSeconds = dailyData.isNotEmpty ? 999999 : 0;
        String maxDay = '';

        for (final data in dailyData) {
          final seconds = data['total_seconds'] as int? ?? 0;
          if (seconds > maxSeconds) {
            maxSeconds = seconds;
            maxDay = data['date'] as String? ?? '';
          }
          if (seconds < minSeconds && seconds > 0) {
            minSeconds = seconds;
          }
        }

        final avgSeconds = _selectedTimeRange <= 0 ? 0 : totalSeconds ~/ _selectedTimeRange;
        
        // Compare selected period against the immediately previous period.
        String trendText = '0%';
        IconData trendIcon = FluentIcons.remove;
        Color trendColor = Colors.grey;

        if (previousPeriodSeconds == 0 && totalSeconds > 0) {
          trendText = 'New';
          trendIcon = FluentIcons.up;
          trendColor = Colors.orange;
        } else if (previousPeriodSeconds > 0) {
          final change =
              ((totalSeconds - previousPeriodSeconds) / previousPeriodSeconds * 100)
                  .round();

          if (change > 0) {
            trendText = '+$change%';
            trendIcon = FluentIcons.up;
            trendColor = Colors.orange;
          } else if (change < 0) {
            trendText = '$change%';
            trendIcon = FluentIcons.down;
            trendColor = Colors.green;
          }
        }

        final cards = <Widget>[
          _QuickStatCard(
            icon: FluentIcons.timer,
            title: 'Total Time',
            value: _formatTime(totalSeconds),
            subtitle: 'Last $_selectedTimeRange days',
            accentColor: theme.accentColor,
            isLight: isLight,
          ),
          _QuickStatCard(
            icon: FluentIcons.calendar,
            title: 'Daily Average',
            value: _formatTime(avgSeconds),
            subtitle: 'Per day',
            accentColor: Colors.teal,
            isLight: isLight,
          ),
          _QuickStatCard(
            icon: FluentIcons.trophy2,
            title: 'Peak Day',
            value: maxDay.isEmpty ? '—' : DateFormat('EEE').format(DateTime.parse(maxDay)),
            subtitle: maxDay.isEmpty ? 'No data' : _formatTime(maxSeconds),
            accentColor: Colors.orange,
            isLight: isLight,
          ),
          _QuickStatCard(
            icon: trendIcon,
            title: 'Trend',
            value: trendText,
            subtitle: 'vs previous $_selectedTimeRange days',
            accentColor: trendColor,
            isLight: isLight,
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 980;

            if (!isCompact) {
              return Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[2]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[3]),
                ],
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

  Widget _buildDailyChart(FluentThemeData theme, bool isLight) {
    return Consumer<ScreenTimeProvider>(
      builder: (context, provider, child) {
        final dailyData = provider.dailyUsage;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 700;
            final safeCount = dailyData.isEmpty ? 1 : dailyData.length;
            final minSlotWidth = isCompact ? 26.0 : 32.0;
            final targetChartWidth = (safeCount * minSlotWidth) + 72;
            final chartWidth = targetChartWidth > constraints.maxWidth
                ? targetChartWidth
                : constraints.maxWidth;
            final barWidth =
                ((chartWidth - 72) / (safeCount * 1.8)).clamp(8.0, 32.0).toDouble();

            int xAxisLabelStep = 1;
            if (dailyData.length > 1) {
              final maxLabels =
                  ((constraints.maxWidth - 56) / 42).floor().clamp(2, dailyData.length).toInt();
              xAxisLabelStep = (dailyData.length / maxLabels).ceil();
            }

            return Container(
              padding: const EdgeInsets.all(24),
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
                  if (isCompact)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Screen Time',
                          style: theme.typography.bodyStrong,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your usage over the past $_selectedTimeRange days',
                          style: theme.typography.caption?.copyWith(
                            color: isLight ? Colors.grey[130] : Colors.grey[100],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Last $_selectedTimeRange days',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.accentColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Daily Screen Time',
                              style: theme.typography.bodyStrong,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your usage over the past $_selectedTimeRange days',
                              style: theme.typography.caption?.copyWith(
                                color: isLight ? Colors.grey[130] : Colors.grey[100],
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Last $_selectedTimeRange days',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.accentColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: isCompact ? 200 : 220,
                    child: dailyData.isEmpty
                        ? _buildEmptyState(theme, isLight, FluentIcons.bar_chart4, 'No usage data available')
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: chartWidth,
                              child: BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceAround,
                                  maxY: _getMaxY(dailyData),
                                  barTouchData: BarTouchData(
                                    enabled: true,
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipColor: (group) => isLight
                                          ? Colors.white
                                          : const Color(0xFF3D3D3D),
                                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                        final date = DateTime.parse(
                                          dailyData[groupIndex]['date'] as String,
                                        );
                                        final hours = rod.toY ~/ 3600;
                                        final minutes = (rod.toY % 3600) ~/ 60;
                                        return BarTooltipItem(
                                          '${DateFormat('MMM d').format(date)}\n${hours}h ${minutes}m',
                                          TextStyle(
                                            color: isLight ? Colors.grey[160] : Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  titlesData: FlTitlesData(
                                    show: true,
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (value, meta) {
                                          final index = value.toInt();
                                          if (index < 0 || index >= dailyData.length) {
                                            return const SizedBox();
                                          }

                                          final dateStr = dailyData[index]['date'] as String;
                                          final date = DateTime.parse(dateStr);
                                          final isToday =
                                              DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateStr;
                                          final shouldShow = isToday || index % xAxisLabelStep == 0;

                                          if (!shouldShow) {
                                            return const SizedBox();
                                          }

                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text(
                                              isToday ? 'Today' : DateFormat('E').format(date),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isToday
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: isToday
                                                    ? theme.accentColor
                                                    : (isLight
                                                        ? Colors.grey[130]
                                                        : Colors.grey[100]),
                                              ),
                                            ),
                                          );
                                        },
                                        reservedSize: 30,
                                      ),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (value, meta) {
                                          final hours = value ~/ 3600;
                                          return Text(
                                            '${hours}h',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isLight ? Colors.grey[130] : Colors.grey[100],
                                            ),
                                          );
                                        },
                                        reservedSize: 35,
                                        interval: 3600,
                                      ),
                                    ),
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    horizontalInterval: 3600,
                                    getDrawingHorizontalLine: (value) {
                                      return FlLine(
                                        color: isLight
                                            ? Colors.grey[50]
                                            : Colors.grey[150].withValues(alpha: 0.2),
                                        strokeWidth: 1,
                                      );
                                    },
                                  ),
                                  barGroups: dailyData.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final data = entry.value;
                                    final isToday =
                                        DateFormat('yyyy-MM-dd').format(DateTime.now()) == data['date'];
                                    return BarChartGroupData(
                                      x: index,
                                      barRods: [
                                        BarChartRodData(
                                          toY: (data['total_seconds'] as int).toDouble(),
                                          gradient: LinearGradient(
                                            colors: isToday
                                                ? [theme.accentColor.lighter, theme.accentColor]
                                                : [
                                                    theme.accentColor.withValues(alpha: 0.7),
                                                    theme.accentColor.withValues(alpha: 0.9),
                                                  ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                          width: barWidth,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(4),
                                            topRight: Radius.circular(4),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopAppsCard(FluentThemeData theme, bool isLight) {
    return Consumer<ScreenTimeProvider>(
      builder: (context, provider, child) {
        final apps = provider.aggregatedUsage.take(5).toList();

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
                  Icon(
                    FluentIcons.app_icon_default,
                    size: 16,
                    color: isLight ? Colors.grey[130] : Colors.grey[100],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (apps.isEmpty)
                _buildEmptyState(theme, isLight, FluentIcons.app_icon_default, 'No apps tracked yet')
              else
                ...apps.asMap().entries.map((entry) {
                  final index = entry.key;
                  final app = entry.value;
                  return _AppListItem(
                    rank: index + 1,
                    name: app.displayName,
                    time: app.formattedTime,
                    percentage: app.percentage,
                    theme: theme,
                    isLight: isLight,
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsagePatternCard(FluentThemeData theme, bool isLight) {
    return Consumer2<ScreenTimeProvider, SettingsProvider>(
      builder: (context, provider, settings, child) {
        // Calculate Insights dynamically
        final String productiveTime;
        final String totalTime;
        final String focusSessions;
        final String breakStatus;
        Color? breakColor;

        if (provider.totalSecondsToday == 0) {
          productiveTime = 'No data yet';
          totalTime = 'No data yet';
          focusSessions = '0 sessions';
          breakStatus = 'Start tracking!';
          breakColor = Colors.grey[100];
        } else {
          // Calculate Productive Time String
          double pScore = provider.focusScore;
          if (pScore >= 80) {
            productiveTime = 'Excellent focus';
          } else if (pScore >= 50) {
            productiveTime = 'Good focus';
          } else {
            productiveTime = 'Needs improvement';
          }

          // Calculate Total Time Insight String
          int hours = provider.totalSecondsToday ~/ 3600;
          if (hours > 8) {
            totalTime = 'Very High (>8h)';
          } else if (hours > 4) {
            totalTime = 'Moderate (4h-8h)';
          } else {
            totalTime = 'Light (<4h)';
          }

          // Calculate focus sessions (matching dashboard focus score rule)
          focusSessions = '${provider.focusScore.toStringAsFixed(0)}%';

          // Break Status Insight
          if (hours > 2 && pScore < 30) {
            breakStatus = 'Take more breaks!';
            breakColor = Colors.orange;
          } else {
            breakStatus = 'Good pacing';
            breakColor = Colors.green;
          }
        }

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
                'Usage Insights',
                style: theme.typography.bodyStrong,
              ),
              Icon(
                FluentIcons.insights,
                size: 16,
                color: isLight ? Colors.grey[130] : Colors.grey[100],
              ),
            ],
          ),
          const SizedBox(height: 16),
            _InsightRow(
              icon: FluentIcons.sunny,
              title: 'Productivity Level',
              value: productiveTime,
              isLight: isLight,
            ),
            const SizedBox(height: 12),
            _InsightRow(
              icon: FluentIcons.timer,
              title: 'Daily Load',
              value: totalTime,
              isLight: isLight,
            ),
            const SizedBox(height: 12),
            _InsightRow(
              icon: FluentIcons.red_eye,
              title: 'Focus Score',
              value: focusSessions,
              valueColor: Colors.green,
              isLight: isLight,
            ),
            const SizedBox(height: 12),
            _InsightRow(
              icon: breakColor == Colors.orange ? FluentIcons.warning : FluentIcons.check_mark,
              title: 'Screen Pacing',
              value: breakStatus,
              valueColor: breakColor,
              isLight: isLight,
            ),
          ],
        ),
      );
    });
  }

  Widget _buildTrendsCard(FluentThemeData theme, bool isLight) {
    return Consumer<ScreenTimeProvider>(
      builder: (context, provider, child) {
        final currentPeriod = provider.currentPeriodTotalSeconds;
        final previousPeriod = provider.previousPeriodTotalSeconds;
        final maxValue =
            currentPeriod > previousPeriod ? currentPeriod : previousPeriod;

        String deltaLabel = 'No change from previous period';
        if (previousPeriod == 0 && currentPeriod > 0) {
          deltaLabel = 'First tracked period in this range';
        } else if (previousPeriod > 0) {
          final deltaPercent =
              ((currentPeriod - previousPeriod) / previousPeriod * 100).round();
          if (deltaPercent > 0) {
            deltaLabel = '+$deltaPercent% more than previous $_selectedTimeRange days';
          } else if (deltaPercent < 0) {
            deltaLabel = '$deltaPercent% less than previous $_selectedTimeRange days';
          }
        }

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
              Text(
                'Period Comparison',
                style: theme.typography.bodyStrong,
              ),
              const SizedBox(height: 16),
              _ComparisonBar(
                label: 'Current $_selectedTimeRange days',
                value: currentPeriod,
                maxValue: maxValue,
                color: theme.accentColor,
                isLight: isLight,
              ),
              const SizedBox(height: 16),
              _ComparisonBar(
                label: 'Previous $_selectedTimeRange days',
                value: previousPeriod,
                maxValue: maxValue,
                color: Colors.grey[100],
                isLight: isLight,
              ),
              const SizedBox(height: 16),
              Text(
                deltaLabel,
                style: theme.typography.caption?.copyWith(
                  color: isLight ? Colors.grey[130] : Colors.grey[100],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(FluentThemeData theme, bool isLight, IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
              color: isLight ? Colors.grey[90] : Colors.grey[100],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: isLight ? Colors.grey[130] : Colors.grey[100],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getMaxY(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 3600;
    int maxSeconds = 0;
    for (final d in data) {
      final seconds = d['total_seconds'] as int? ?? 0;
      if (seconds > maxSeconds) maxSeconds = seconds;
    }
    return ((maxSeconds / 3600).ceil() * 3600).toDouble().clamp(3600, double.infinity);
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

class _TimeRangeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final bool isFirst;
  final bool isLast;
  final bool isLight;

  const _TimeRangeButton({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
  final String subtitle;
  final Color accentColor;
  final bool isLight;

  const _QuickStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.accentColor,
    required this.isLight,
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: accentColor),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.typography.subtitle?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: theme.typography.caption?.copyWith(
              color: isLight ? Colors.grey[130] : Colors.grey[100],
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppListItem extends StatelessWidget {
  final int rank;
  final String name;
  final String time;
  final double percentage;
  final FluentThemeData theme;
  final bool isLight;

  const _AppListItem({
    required this.rank,
    required this.name,
    required this.time,
    required this.percentage,
    required this.theme,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
                  name,
                  style: theme.typography.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ProgressBar(value: percentage),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            time,
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

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;
  final bool isLight;

  const _InsightRow({
    required this.icon,
    required this.title,
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
          size: 16,
          color: theme.accentColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: theme.typography.caption?.copyWith(
              color: isLight ? Colors.grey[130] : Colors.grey[100],
            ),
          ),
        ),
        Text(
          value,
          style: theme.typography.caption?.copyWith(
            fontWeight: FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _ComparisonBar extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color color;
  final bool isLight;

  const _ComparisonBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final percentage = maxValue > 0 ? (value / maxValue * 100) : 0.0;

    final hours = value ~/ 3600;
    final minutes = (value % 3600) ~/ 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.typography.caption?.copyWith(
                color: isLight ? Colors.grey[130] : Colors.grey[100],
              ),
            ),
            Text(
              '${hours}h ${minutes}m',
              style: theme.typography.body?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: isLight ? Colors.grey[40] : Colors.grey[150],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percentage / 100,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
