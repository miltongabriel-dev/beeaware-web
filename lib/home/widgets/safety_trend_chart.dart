import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/beeaware_theme.dart';

/// One category's line on the trend chart — e.g. "Violência" in red,
/// aligned month-by-month with every other series passed to
/// [SafetyTrendChart].
class TrendSeries {
  final String label;
  final Color color;
  final List<double> values;

  /// Per-month breakdown by crime subtype (e.g. {"Roubo a transeunte": 4,
  /// "Furto": 2}) — same length as [values], index-aligned. Powers the
  /// touch tooltip only; the line itself is drawn from [values] alone. An
  /// empty map at a given index just means the tooltip falls back to the
  /// plain total for that point.
  final List<Map<String, int>> subtypeBySpot;

  const TrendSeries({
    required this.label,
    required this.color,
    required this.values,
    this.subtypeBySpot = const [],
  });
}

class SafetyTrendChart extends StatelessWidget {
  final List<TrendSeries> series;
  final List<DateTime> months;

  const SafetyTrendChart({
    super.key,
    required this.series,
    required this.months,
  });

  @override
  Widget build(BuildContext context) {
    // A série pode vir presente mas totalmente zerada (ex.: nenhum
    // incidente de trânsito perto do ponto escolhido) — isso ainda é um
    // gráfico válido (linha reta em zero), diferente de months vazio, que
    // é a única situação em que não há nada pra desenhar.
    if (months.isEmpty || series.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.noDataAvailable,
            style: const TextStyle(color: BeeAwareTheme.textSecondary),
          ),
        ),
      );
    }

    final locale = Localizations.localeOf(context).toString();
    final maxValue = series
        .expand((s) => s.values)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
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
                      if (i < 0 || i >= months.length) {
                        return const SizedBox.shrink();
                      }

                      final m = months[i];
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          DateFormat.MMM(locale).format(m),
                          style: const TextStyle(
                              fontSize: 10,
                              color: BeeAwareTheme.textSecondary),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (months.length - 1).toDouble(),
              minY: 0,
              maxY: maxValue + 2,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                    final s = series[spot.barIndex];
                    final monthIdx = spot.spotIndex;
                    final subtypes = monthIdx < s.subtypeBySpot.length
                        ? s.subtypeBySpot[monthIdx]
                        : const <String, int>{};

                    // Mais de um subtipo no mesmo ponto: lista os 3 mais
                    // frequentes em vez do total sozinho — abaixo disso
                    // (0 ou 1 subtipo distinto) o total já diz tudo que o
                    // breakdown diria.
                    String text;
                    if (subtypes.length > 1) {
                      final sorted = subtypes.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value));
                      text = sorted
                          .take(3)
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n');
                    } else {
                      text = '${s.label}: ${spot.y.toInt()}';
                    }

                    return LineTooltipItem(
                      text,
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: series
                  .map(
                    (s) => LineChartBarData(
                      isCurved: true,
                      color: s.color,
                      barWidth: 3,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                      spots: List.generate(
                        s.values.length,
                        (i) => FlSpot(i.toDouble(), s.values[i]),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 4,
          children: series
              .map(
                (s) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: s.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      s.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: BeeAwareTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
