import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

class SafetyTrendChart extends StatelessWidget {
  final List<double> values;
  final List<DateTime> months; // 🔥 novo

  const SafetyTrendChart({
    super.key,
    required this.values,
    required this.months,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty || months.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.noDataAvailable,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final locale = Localizations.localeOf(context).toString();
    final maxValue = values.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= months.length)
                    return const SizedBox.shrink();

                  final m = months[i];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat.MMM(locale).format(m),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF6B7280)),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (values.length - 1).toDouble(),
          minY: 0,
          maxY: maxValue + 2,
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              color: const Color(0xFFF59E0B),
              barWidth: 3,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              ),
              spots: List.generate(
                values.length,
                (i) => FlSpot(i.toDouble(), values[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
