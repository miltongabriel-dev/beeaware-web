import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/token_state.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BuyTokensScreen extends StatelessWidget {
  const BuyTokensScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F2E5),
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
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 12),

        // 🔥 HERO
        Container(
          child: Column(
            children: [
              SvgPicture.asset(
                'assets/logo/beeaware_texto.svg',
                width: 160,
              ),
              const SizedBox(height: 10),
              const Text(
                'Choose a plan and explore any area before you go.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color.fromARGB(255, 113, 113, 113),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        _PackageCard(
          title: '5 searches',
          price: '£2',
          tokens: 5,
        ),

        const SizedBox(height: 14),

        _PackageCard(
          title: '15 searches',
          price: '£5',
          tokens: 15,
          highlight: true,
          badge: 'Most popular',
        ),

        const SizedBox(height: 14),

        _PackageCard(
          title: '40 searches',
          price: '£10',
          tokens: 40,
          badge: 'Best value',
        ),

        const SizedBox(height: 26),

        const Text(
          'Secure payments. No subscription required.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),

        const SizedBox(height: 30),
      ],
    );
  }
}

class _PackageCard extends StatefulWidget {
  final String title;
  final String price;
  final int tokens;
  final bool highlight;
  final String? badge;

  const _PackageCard({
    required this.title,
    required this.price,
    required this.tokens,
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
            const SnackBar(content: Text('Credits added')),
          );

          Navigator.pop(context);
        },
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: highlight ? Colors.white : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: highlight
                        ? const Color(0xFFF59E0B)
                        : Colors.grey.shade200,
                    width: highlight ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
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
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.badge!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
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
