import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../state/token_state.dart';
import '../theme/beeaware_theme.dart';

enum _PackageBadge { mostPopular, bestValue }

class BuyTokensScreen extends StatelessWidget {
  const BuyTokensScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: false,
        title: const SizedBox.shrink(), // remove o título
      ),
      body: const _Content(),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 12),

        // 🔥 HERO
        Container(
          child: Column(
            children: [
              Image.asset(
                Localizations.localeOf(context).languageCode == 'pt'
                    ? 'assets/logo/beeaware_wordmark_pt.png'
                    : 'assets/logo/beeaware_wordmark_en.png',
                width: 160,
              ),
              const SizedBox(height: 10),
              Text(
                loc.buyTokensSubtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: BeeAwareTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        const _PackageCard(
          price: '£2',
          priceValue: 2,
          tokens: 5,
          icon: Icons.search,
        ),

        const SizedBox(height: 14),

        const _PackageCard(
          price: '£5',
          priceValue: 5,
          tokens: 15,
          highlight: true,
          badge: _PackageBadge.mostPopular,
          icon: Icons.bolt_outlined,
        ),

        const SizedBox(height: 14),

        const _PackageCard(
          price: '£10',
          priceValue: 10,
          tokens: 40,
          badge: _PackageBadge.bestValue,
          icon: Icons.workspace_premium_outlined,
        ),

        const SizedBox(height: 26),

        Text(
          loc.bonusTokensNotice,
          textAlign: TextAlign.center,
          style:
              const TextStyle(fontSize: 12, color: BeeAwareTheme.textSecondary),
        ),

        const SizedBox(height: 30),
      ],
    );
  }
}

class _PackageCard extends StatefulWidget {
  final String price;
  final double priceValue;
  final int tokens;
  final bool highlight;
  final _PackageBadge? badge;
  final IconData icon;

  const _PackageCard({
    required this.price,
    required this.priceValue,
    required this.tokens,
    required this.icon,
    this.highlight = false,
    this.badge,
  });

  @override
  State<_PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends State<_PackageCard> {
  double _scale = 1;

  void _setScale(double value) {
    if (!mounted) return;
    setState(() => _scale = value);
  }

  @override
  Widget build(BuildContext context) {
    final highlight = widget.highlight;
    final loc = AppLocalizations.of(context)!;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setScale(1.02),
      onExit: (_) => _setScale(1),
      child: GestureDetector(
        onTapDown: (_) => _setScale(0.97),
        onTapUp: (_) => _setScale(1.02),
        onTapCancel: () => _setScale(1),
        onTap: () {
          context.read<TokenState>().addTokens(widget.tokens);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.creditsAdded)),
          );

          Navigator.pop(context);
        },
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: BeeAwareTheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: highlight ? BeeAwareTheme.accent : BeeAwareTheme.border,
                    width: highlight ? 2 : 1,
                  ),
                  boxShadow: BeeAwareTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BeeAwareTheme.primary.withValues(alpha: 0.08),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 22,
                        color: BeeAwareTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.packageSearches(widget.tokens),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            loc.pricePerSearch(
                              '£${(widget.priceValue / widget.tokens).toStringAsFixed(2)}',
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: BeeAwareTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      widget.price,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              // 🔥 BADGE
              if (widget.badge != null)
                Positioned(
                  top: -2,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: BeeAwareTheme.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      widget.badge == _PackageBadge.mostPopular
                          ? loc.badgeMostPopular
                          : loc.badgeBestValue,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: BeeAwareTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
