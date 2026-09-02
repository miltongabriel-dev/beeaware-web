import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../backend/fr_crime_summary_api.dart';
import '../theme/beeaware_theme.dart';
import 'zoom_scaled_polygon_layer.dart';

/// Renders FrCrimeSummaryApi's département-level crime counts as a
/// choropleth — same terciles-based approach as
/// MunicipioEsChoroplethLayer/ConcelhoChoroplethLayer/
/// PoliceForceChoroplethLayer. All 101 French départements get a
/// polygon here (no publication-limit gap the way Spain's municipio
/// layer has). No tap-to-detail here yet, same v1 scope decision already
/// made for the UK/Portugal/Spain layers. Fill/border are zoom-scaled
/// (see ZoomScaledPolygonLayer) so the colours stay legible zoomed out
/// across all 101 départements, not just right after searching one
/// exact address.
class DepartementFrChoroplethLayer extends StatelessWidget {
  final MapController mapController;
  final List<DepartementFrCrimeSummary> summaries;

  const DepartementFrChoroplethLayer({
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
