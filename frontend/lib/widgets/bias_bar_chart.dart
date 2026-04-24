import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BiasBarChart extends StatelessWidget {
  final String attributeName;
  final List<String> groups;
  final List<double> selectionRates;

  // On screens narrower than this, wrap the chart in a horizontal scroll view.
  static const _mobileBreakpoint = 600.0;
  // Minimum pixel width per bar group so they don't crowd on mobile.
  static const _minBarWidth = 72.0;

  const BiasBarChart({
    super.key,
    required this.attributeName,
    required this.groups,
    required this.selectionRates,
  });

  static const _barColors = [
    Color(0xFF185FA5), // primary blue
    Color(0xFFE8715A), // coral
    Color(0xFF1D9E75), // teal
    Color(0xFFBA7517), // amber
    Color(0xFF7B61FF), // purple
    Color(0xFF2CC0C0), // cyan
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Selection Rate by $attributeName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Proportion of candidates hired per group (0 – 1)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              final isMobile = screenWidth < _mobileBreakpoint;
              final minChartWidth = groups.length * _minBarWidth + 60.0;
              final needsScroll = isMobile && minChartWidth > constraints.maxWidth;

              final chart = SizedBox(
                width: needsScroll ? minChartWidth : double.infinity,
                height: 200,
                child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 1.0,
                  minY: 0,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final label = groups[groupIndex];
                        final pct =
                            (rod.toY * 100).toStringAsFixed(1);
                        return BarTooltipItem(
                          '$label\n$pct%',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: 0.2,
                        getTitlesWidget: (value, meta) => Text(
                          '${(value * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= groups.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              groups[i],
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    horizontalInterval: 0.2,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: AppColors.divider,
                      strokeWidth: 1,
                    ),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(groups.length, (i) {
                    final color = _barColors[i % _barColors.length];
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: selectionRates[i].clamp(0.0, 1.0),
                          color: color,
                          width: 36,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 1,
                            color: color.withOpacity(0.07),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ), // BarChart
              ); // SizedBox (chart)

              return needsScroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: chart,
                    )
                  : chart;
            }), // LayoutBuilder
            const SizedBox(height: 8),
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: List.generate(groups.length, (i) {
                final color = _barColors[i % _barColors.length];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      groups[i],
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
