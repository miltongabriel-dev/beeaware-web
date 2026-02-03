import 'package:shared_preferences/shared_preferences.dart';

class ReportRateLimiter {
  static const _keyLastReportAt = 'last_report_at';
  static const Duration cooldown = Duration(minutes: 5);

  /// Retorna true se o user PODE enviar agora
  static Future<bool> canSubmit() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMillis = prefs.getInt(_keyLastReportAt);

    if (lastMillis == null) return true;

    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastMillis);
    final diff = DateTime.now().difference(lastTime);

    return diff >= cooldown;
  }

  /// Quantos segundos faltam para poder enviar novamente
  static Future<Duration> remaining() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMillis = prefs.getInt(_keyLastReportAt);

    if (lastMillis == null) return Duration.zero;

    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastMillis);
    final diff = DateTime.now().difference(lastTime);

    if (diff >= cooldown) return Duration.zero;
    return cooldown - diff;
  }

  /// Marca um submit bem-sucedido
  static Future<void> markSubmitted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyLastReportAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }
}
