import 'package:flutter/material.dart';
import 'map_incident.dart';

/// 🔒 FLAG DE SEGURANÇA
/// Enquanto true → public pins viram dots
/// Community pins continuam iguais
const bool USE_NEW_PUBLIC_PINS = true;

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

  // ⚪ PUBLIC — cor por severidade (dot)
  Color _publicColorBySeverity() {
    switch (widget.incident.severity) {
      case IncidentSeverity.high:
        return const Color(0xFFF44336); // vermelho
      case IncidentSeverity.medium:
        return const Color(0xFFFF9800); // laranja
      case IncidentSeverity.low:
      default:
        return const Color(0xFFFFC107); // âmbar
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
            color: _publicColorBySeverity().withOpacity(0.85),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCommunity = !widget.incident.isOfficial;

    /// Só aplica o novo visual para PUBLIC se a flag estiver ligada
    final bool useDot = USE_NEW_PUBLIC_PINS && !isCommunity;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await _controller.forward();
        await _controller.reverse();
        widget.onTap();
      },
      child: ScaleTransition(
        scale: _controller,
        child: useDot ? _buildPublicDot() : _buildCommunityBee(),
      ),
    );
  }
}
