import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../state/token_state.dart';

class SearchAddressScreen extends StatefulWidget {
  const SearchAddressScreen({super.key});

  @override
  State<SearchAddressScreen> createState() => _SearchAddressScreenState();
}

class _SearchAddressScreenState extends State<SearchAddressScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch() {
    final loc = AppLocalizations.of(context)!;
    final tokenState = context.read<TokenState>();
    final query = _controller.text.trim();

    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.typeAddressToSearch)),
      );
      return;
    }

    if (!tokenState.hasTokens) {
      _showNoTokensDialog();
      return;
    }

    // Mock: por enquanto só mostra mensagem
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.searchingNearMock(query))),
    );
  }

  void _showNoTokensDialog() {
    final loc = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(loc.noTokensLeftTitle),
        content: Text(loc.noTokensLeftContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/buyTokens');
            },
            child: Text(loc.buyTokensButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final tokens = context.watch<TokenState>().tokens;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.searchAddressTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.tokensRemaining(tokens)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: loc.addressOrPostcodeHint,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _onSearch(),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _onSearch,
              child: Text(loc.searchButton),
            ),
          ],
        ),
      ),
    );
  }
}
