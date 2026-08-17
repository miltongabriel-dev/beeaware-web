import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:aware/state/token_state.dart';
import 'package:aware/report/buy_tokens_screen.dart';
import 'package:aware/theme/beeaware_theme.dart';
import 'package:aware/l10n/app_localizations.dart';

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
              color: BeeAwareTheme.surface,
              shape: BoxShape.circle,
              boxShadow: BeeAwareTheme.cardShadow,
            ),
            child: const Icon(
              Icons.settings,
              color: BeeAwareTheme.textPrimary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  void _openMenu(BuildContext context, int tokens) async {
    final loc = AppLocalizations.of(context)!;
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
              Text(loc.accountLabel),
              Text(loc.tokensCount(tokens)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'buy',
          child: Row(
            children: [
              const Icon(Icons.toll, size: 18),
              const SizedBox(width: 10),
              Text(loc.buyTokensButton),
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
  }
}
