import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// One choropleth area: its severity colour and the ring(s) that make up
/// its polygon (see e.g. MunicipalityCrimeSummary.polygons for why holes
/// are dropped and multi-part geometry becomes several separate rings).
class ChoroplethArea {
  final Color color;
  final List<List<LatLng>> polygons;

  const ChoroplethArea({required this.color, required this.polygons});
}

/// Shared by every country's choropleth layer (Brazil, UK, Portugal,
/// Spain): renders each [ChoroplethArea] as flutter_map [Polygon]s, with
/// fill opacity and border width that INCREASE as the map zooms out.
///
/// Without this, a fixed low opacity (chosen so pins/labels stay legible
/// when the map is zoomed into a single searched address) makes a
/// choropleth of hundreds of areas — each shrunk to a few screen pixels
/// at country/state zoom — visually disappear against the base map
/// tiles. Reported live: the colours were only "clearly" visible right
/// after searching an exact address (zoom ~15), not when zooming out to
/// see a macro region. Scaling opacity/border width up as zoom decreases
/// keeps today's look at address-level zoom while making the macro view
/// actually legible — the same mapEventStream-listening pattern
/// home_screen.dart's own _ZoomControl already uses for its slider.
class ZoomScaledPolygonLayer extends StatefulWidget {
  final MapController mapController;
  final List<ChoroplethArea> areas;

  const ZoomScaledPolygonLayer({
    super.key,
    required this.mapController,
    required this.areas,
  });

  @override
  State<ZoomScaledPolygonLayer> createState() =>
      _ZoomScaledPolygonLayerState();
}

class _ZoomScaledPolygonLayerState extends State<ZoomScaledPolygonLayer> {
  // Below _macroZoom the fill/border sit at their most saturated (a
  // country/state-level "macro" view, e.g. zoomed all the way out); at or
  // above _detailZoom they're back to the original, address-search-
  // friendly look. Bracket chosen around home_screen.dart's own
  // initialZoom: 15 (a searched address) versus a whole-country view.
  static const double _macroZoom = 5;
  static const double _detailZoom = 13;

  late double _zoom = widget.mapController.camera.zoom;
  StreamSubscription<MapEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.mapController.mapEventStream.listen((event) {
      final z = event.camera.zoom;
      if (mounted && (z - _zoom).abs() > 0.05) {
        setState(() => _zoom = z);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.areas.isEmpty) return const SizedBox.shrink();

    final t = ((_detailZoom - _zoom) / (_detailZoom - _macroZoom))
        .clamp(0.0, 1.0);
    final fillAlpha = _lerp(0.28, 0.65, t);
    final borderAlpha = _lerp(0.55, 0.85, t);
    final borderWidth = _lerp(1.0, 2.5, t);

    final polygons = <Polygon>[];
    for (final area in widget.areas) {
      for (final ring in area.polygons) {
        polygons.add(
          Polygon(
            points: ring,
            color: area.color.withValues(alpha: fillAlpha),
            borderColor: area.color.withValues(alpha: borderAlpha),
            borderStrokeWidth: borderWidth,
          ),
        );
      }
    }

    return PolygonLayer(polygons: polygons);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
