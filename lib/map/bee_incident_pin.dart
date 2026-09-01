import 'package:flutter/material.dart';
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

  Widget _buildPublicDot() {
    return SizedBox(
      width: 24, // área de toque confortável
      height: 24,
      child: Center(
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                SeverityColors.of(widget.incident.severity).withOpacity(0.85),
          ),
        ),
      ),
    );
  }

  // News-derived pins only ever resolve to a municipality centroid, never
  // a real reported point (see NewsPinsApi's own header) — a halo
  // ring around a smaller dot reads as "somewhere in this area" rather
  // than the solid dot's "confirmed here", the same geographic-honesty
  // distinction the backend RPCs already enforce.
  Widget _buildApproximateHalo() {
    final color = SeverityColors.of(widget.incident.severity);
    return SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.16),
                border: Border.all(color: color.withOpacity(0.55), width: 1.5),
              ),
            ),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCommunity = !widget.incident.isOfficial;

    Widget dot;
    if (isCommunity) {
      dot = _buildCommunityBee();
    } else if (widget.incident.isApproximate) {
      dot = _buildApproximateHalo();
    } else {
      dot = _buildPublicDot();
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
