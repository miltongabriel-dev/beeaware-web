import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../backend/uk_crime_summary_api.dart';
import '../theme/beeaware_theme.dart';
import 'zoom_scaled_polygon_layer.dart';

/// Renders UkCrimeSummaryApi's Police Force-level crime counts as a
/// choropleth — same terciles-based approach as MunicipalityChoroplethLayer,
/// one tier coarser (43 England & Wales forces instead of municipalities).
/// No tap-to-detail here yet: the ask was area colour, not a drill-down
/// screen — see UkPoliceAdapter's header for why ~13 of the 43 forces
/// never appear (a real data.police.uk limitation, not a bug here).
/// Fill/border are zoom-scaled (see ZoomScaledPolygonLayer) so the colours
/// stay legible zoomed out, not just right after searching one address.
class PoliceForceChoroplethLayer extends StatelessWidget {
  final MapController mapController;
  final List<PoliceForceCrimeSummary> summaries;

  const PoliceForceChoroplethLayer({
    super.key,
    required this.mapController,
    required this.summaries,
  });

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) return const SizedBox.shrink();

    final thresholds = _terciles(summaries.map((s) => s.totalCount).toList());

    final areas = [
      for (final summary in summaries)
        ChoroplethArea(
          color: _colorFor(summary.totalCount, thresholds),
          polygons: summary.polygons,
        ),
    ];

    return ZoomScaledPolygonLayer(mapController: mapController, areas: areas);
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
