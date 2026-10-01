import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'incident_icons.dart';
import 'map_incident.dart';
import '../theme/beeaware_theme.dart';

class BeeIncidentPin extends StatefulWidget {
  final MapIncident incident;
  final VoidCallback onTap;

  const BeeIncidentPin({
    super.key,
    required this.incident,
    required this.onTap,
  });

  @override
  State<BeeIncidentPin> createState() => _BeeIncidentPinState();
}

class _BeeIncidentPinState extends State<BeeIncidentPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    lowerBound: 0.96,
    upperBound: 1.08,
  )..value = 1.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 🐝 COMMUNITY — mantém o comportamento atual (assets por severidade)
  String _communityBeeAsset() {
    switch (widget.incident.severity) {
      case IncidentSeverity.high:
        return 'assets/pins/bee_high.png';
      case IncidentSeverity.medium:
        return 'assets/pins/bee_medium.png';
      case IncidentSeverity.low:
      default:
        return 'assets/pins/bee_low.png';
    }
  }

  Widget _buildCommunityBee() {
    return SizedBox(
      width: 42,
      height: 42,
      child: Image.asset(
        _communityBeeAsset(),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }

  // Official incidents: a severity-coloured badge with the incident type's
  // icon (IncidentIcons) inside. Replaced a bare 10px severity dot that
  // users couldn't read — it showed how severe, never what happened.
  //
  // News-derived pins only ever resolve to a municipality centroid, never
  // a real reported point (see NewsPinsApi's own header) — those get a
  // dashed ring plus a soft halo, reading as "somewhere in this area"
  // rather than the solid ring's "confirmed here", the same
  // geographic-honesty distinction the backend RPCs already enforce.
  Widget _buildOfficialBadge({required bool approximate}) {
    final severity = widget.incident.severity;
    final color = SeverityColors.of(severity);
    // White on the low-severity yellow is near-unreadable, so that one
    // badge gets a dark glyph instead.
    final iconColor = severity == IncidentSeverity.low
        ? _lowSeverityIconColor
        : Colors.white;

    final badge = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: approximate ? null : Border.all(color: Colors.white, width: 2),
        boxShadow: approximate
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Icon(IncidentIcons.of(widget.incident), size: 17, color: iconColor),
    );

    return SizedBox(
      width: 42,
      height: 42,
      child: Center(
        child: approximate
            ? Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                ),
                alignment: Alignment.center,
                child: CustomPaint(
                  foregroundPainter: _DashedRingPainter(),
                  child: badge,
                ),
              )
            : badge,
      ),
    );
  }

  static const Color _lowSeverityIconColor = Color(0xFF4A3800);

  @override
  Widget build(BuildContext context) {
    final bool isCommunity = !widget.incident.isOfficial;

    Widget dot;
    if (isCommunity) {
      dot = _buildCommunityBee();
    } else {
      dot = _buildOfficialBadge(approximate: widget.incident.isApproximate);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await _controller.forward();
        await _controller.reverse();
        widget.onTap();
      },
      child: ScaleTransition(
        scale: _controller,
        child: dot,
      ),
    );
  }
}

/// White dashed ring around an approximate-location badge — Flutter's
/// Border can't dash, so it's painted as short arcs.
class _DashedRingPainter extends CustomPainter {
  static const int _dashes = 12;
  static const double _gapFraction = 0.4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 1,
    );
    const sweep = 2 * math.pi / _dashes;
    for (var i = 0; i < _dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * (1 - _gapFraction), false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) => false;
}
