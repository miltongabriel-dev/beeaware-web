import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/beeaware_theme.dart';

/// Global bottom navigation shell: Início / Mapa / (Reportar) / Alertas /
/// Perfil. Same pill-shaped bar + raised central button that used to live
/// inside home_screen.dart's map-only `_BottomBar` — moved here since the
/// bar is now app-wide (RootScreen.bottomNavigationBar) rather than a
/// widget drawn on top of the map.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onReport;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    // Height/offset match the map-only bottom bar this replaced exactly
    // (92 / bottom: 16 for the raised button) — a shorter box here clips
    // the top of the 66px-tall central button, since Stack's default
    // clipBehavior is hardEdge.
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      BarIcon(
                        icon: PhosphorIconsRegular.house,
                        activeIcon: PhosphorIconsFill.house,
                        tooltip: loc.bottomNavHome,
                        selected: currentIndex == 0,
                        onTap: () => onTabSelected(0),
                      ),
                      BarIcon(
                        icon: PhosphorIconsRegular.mapTrifold,
                        activeIcon: PhosphorIconsFill.mapTrifold,
                        tooltip: loc.bottomNavMap,
                        selected: currentIndex == 1,
                        onTap: () => onTabSelected(1),
                      ),
                    ],
                  ),
                  // Empty middle — reserved for the raised central button
                  // positioned on top of this bar below.
                  const SizedBox(width: 56),
                  Row(
                    children: [
                      BarIcon(
                        icon: PhosphorIconsRegular.bell,
                        activeIcon: PhosphorIconsFill.bell,
                        tooltip: loc.bottomNavAlerts,
                        selected: currentIndex == 2,
                        onTap: () => onTabSelected(2),
                      ),
                      BarIcon(
                        icon: PhosphorIconsRegular.user,
                        activeIcon: PhosphorIconsFill.user,
                        tooltip: loc.bottomNavProfile,
                        selected: currentIndex == 3,
                        onTap: () => onTabSelected(3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 16,
              child: AnimatedCentralButton(onTap: onReport),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single tab icon — active tab in brand orange with a filled glyph,
/// inactive in the theme's muted "aux" tone with the outline glyph. The
/// filled/outline swap (not just a color change) is what makes the active
/// tab actually read as selected at this icon size.
class BarIcon extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  const BarIcon({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(selected ? activeIcon : icon, size: 22),
        color: selected ? BeeAwareTheme.primary : BeeAwareTheme.textAux,
        iconSize: 22,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
        onPressed: onTap,
      ),
    );
  }
}

/// The raised "Reportar" button — solid brand-orange circle with a plain
/// white plus, matching the reference design exactly (no mascot icon, no
/// pulsing glow — just a flat FAB with a white ring separating it from the
/// bar behind it).
class AnimatedCentralButton extends StatefulWidget {
  final VoidCallback onTap;

  const AnimatedCentralButton({super.key, required this.onTap});

  @override
  State<AnimatedCentralButton> createState() => _AnimatedCentralButtonState();
}

class _AnimatedCentralButtonState extends State<AnimatedCentralButton> {
  double _scale = 1.0;

  void _setScale(double value) {
    if (!mounted) return;
    setState(() => _scale = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setScale(1.05),
      onExit: (_) => _setScale(1.0),
      child: GestureDetector(
        onTapDown: (_) => _setScale(0.94),
        onTapUp: (_) {
          _setScale(1.05);
          widget.onTap();
        },
        onTapCancel: () => _setScale(1.0),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: BeeAwareTheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              PhosphorIconsBold.plus,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
