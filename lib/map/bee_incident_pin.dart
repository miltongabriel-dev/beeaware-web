import 'package:flutter/material.dart';

import 'map_incident.dart';

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

  String _pinAsset(MapIncident incident) {
    // 🏛️ oficial → neutro
    if (incident.isOfficial) {
      return 'assets/pins/bee_official.png';
    }

    // 🐝 comunidade → severidade
    switch (incident.severity) {
      case IncidentSeverity.high:
        return 'assets/pins/bee_high.png';
      case IncidentSeverity.medium:
        return 'assets/pins/bee_medium.png';
      case IncidentSeverity.low:
      default:
        return 'assets/pins/bee_low.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await _controller.forward();
        await _controller.reverse();
        widget.onTap();
      },
      child: ScaleTransition(
        scale: _controller,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Image.asset(
            _pinAsset(widget.incident),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
