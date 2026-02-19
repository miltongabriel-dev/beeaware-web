import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    final tokenState = context.read<TokenState>();
    final query = _controller.text.trim();

    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type an address to search.')),
      );
      return;
    }

    if (!tokenState.hasTokens) {
      _showNoTokensDialog();
      return;
    }

    // Mock: por enquanto só mostra mensagem
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Searching near: $query (mock)')),
    );
  }

  void _showNoTokensDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No tokens left'),
        content: const Text(
          'You have no search tokens remaining.\n\nBuy more tokens to continue searching.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/buyTokens');
            },
            child: const Text('Buy Tokens'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.watch<TokenState>().tokens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Address'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tokens remaining: $tokens'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Address or postcode',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _onSearch(),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _onSearch,
              child: const Text('Search'),
            ),
          ],
        ),
      ),
    );
  }
}
