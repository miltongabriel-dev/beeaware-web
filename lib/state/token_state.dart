import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TokenState extends ChangeNotifier {
  int _tokens = 5;

  int get tokens => _tokens;

  bool get hasTokens => _tokens > 0;

  /// 🔹 carregar tokens do Supabase (após login)
  Future<void> loadTokens() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final res = await Supabase.instance.client
        .from('user_tokens')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();

    if (res != null) {
      _tokens = res['tokens'] ?? 0;
    } else {
      // primeiro login → cria conta com tokens grátis
      await Supabase.instance.client.from('user_tokens').insert({
        'user_id': user.id,
        'tokens': 5,
      });

      _tokens = 5;
    }

    notifyListeners();
  }

  /// 🔹 consumir token
  Future<bool> useToken() async {
    if (_tokens <= 0) return false;

    _tokens--;
    notifyListeners();

    await _syncToBackend();
    return true;
  }

  /// 🔹 adicionar tokens (compra)
  Future<void> addTokens(int amount) async {
    if (amount <= 0) return;

    _tokens += amount;
    notifyListeners();

    await _syncToBackend();
  }

  /// 🔹 sincronizar com Supabase
  Future<void> _syncToBackend() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await Supabase.instance.client
        .from('user_tokens')
        .update({'tokens': _tokens}).eq('user_id', user.id);
  }

  /// 🔹 reset (logout)
  void clear() {
    _tokens = 0;
    notifyListeners();
  }

  void setTokens(int value) {
    _tokens = value <= 0 ? 5 : value;
    notifyListeners();
  }
}
