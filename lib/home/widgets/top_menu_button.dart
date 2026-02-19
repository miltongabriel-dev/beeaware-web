import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aware/state/token_state.dart';
import 'package:aware/report/buy_tokens_screen.dart';

class TopMenuButton extends StatelessWidget {
  const TopMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<TokenState>().tokens;

    return Positioned(
      top: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _openMenu(context, tokens),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.settings,
              color: Color(0xFF2F3A4A),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  void _openMenu(BuildContext context, int tokens) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final result = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 16, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Account'),
              Text('$tokens tokens'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'buy',
          child: Row(
            children: [
              Icon(Icons.toll, size: 18),
              SizedBox(width: 10),
              Text('Buy Tokens'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'data',
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 18),
              SizedBox(width: 10),
              Text('Data Sources'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'about',
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 10),
              Text('About BeeAware'),
            ],
          ),
        ),
      ],
    );

    if (result == 'buy') {
      // evita o warning de usar context após await em alguns casos
      if (!context.mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BuyTokensScreen()),
      );
    }

    // por enquanto data/about vamos ligar depois (fácil)
  }
}
