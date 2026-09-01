import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../backend/es_crime_summary_api.dart';
import '../theme/beeaware_theme.dart';

/// Renders EsCrimeSummaryApi's municipio-level crime counts as a
/// choropleth — same terciles-based approach as
/// ConcelhoChoroplethLayer/PoliceForceChoroplethLayer. Only the 427
/// Spanish municipios over ~20,000 inhabitants get a polygon here — see
/// EsCrimeSummaryApi's doc comment for why. No tap-to-detail here yet,
/// same v1 scope decision already made for the UK/Portugal layers.
class MunicipioEsChoroplethLayer extends StatelessWidget {
  final List<MunicipioEsCrimeSummary> summaries;

  const MunicipioEsChoroplethLayer({super.key, required this.summaries});

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) return const SizedBox.shrink();

    final thresholds = _terciles(summaries.map((s) => s.totalCount).toList());

    final polygons = <Polygon>[];
    for (final summary in summaries) {
      final color = _colorFor(summary.totalCount, thresholds);
      for (final ring in summary.polygons) {
        polygons.add(
          Polygon(
            points: ring,
            color: color.withOpacity(0.28),
            borderColor: color.withOpacity(0.55),
            borderStrokeWidth: 1,
          ),
        );
      }
    }

    return PolygonLayer(polygons: polygons);
  }

  static (int, int) _terciles(List<int> counts) {
    if (counts.isEmpty) return (0, 0);
    final sorted = [...counts]..sort();
    final low =
        sorted[(sorted.length * 0.33).floor().clamp(0, sorted.length - 1)];
    final high =
        sorted[(sorted.length * 0.66).floor().clamp(0, sorted.length - 1)];
    return (low, high);
  }

  static Color _colorFor(int totalCount, (int, int) thresholds) {
    final (low, high) = thresholds;
    if (totalCount > high) return SeverityColors.high;
    if (totalCount > low) return SeverityColors.medium;
    return SeverityColors.low;
  }
}
