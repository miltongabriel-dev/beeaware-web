import 'package:supabase_flutter/supabase_flutter.dart';

/// The one trusted contact a logged-in user can register (see
/// supabase/migrations/20260904100000_emergency_contacts.sql) to be
/// notified over WhatsApp — with their live location — from the SOS
/// sheet. [phone] is stored however the user typed it (with formatting);
/// [whatsAppDigits] strips it down to the digits wa.me needs.
class EmergencyContact {
  final String name;
  final String phone;

  const EmergencyContact({required this.name, required this.phone});

  String get whatsAppDigits => phone.replaceAll(RegExp(r'[^0-9]'), '');
}

class EmergencyContactApi {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Null when logged out, or when the logged-in user hasn't registered
  /// one yet — both are the same "nothing to show" case to every caller.
  static Future<EmergencyContact?> fetchMine() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final row = await _client
          .from('emergency_contacts')
          .select('name, phone')
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return null;
      final name = row['name'] as String?;
      final phone = row['phone'] as String?;
      if (name == null || phone == null) return null;

      return EmergencyContact(name: name, phone: phone);
    } catch (_) {
      return null;
    }
  }

  /// Upsert on `user_id` — matches the single-contact-per-user unique
  /// index, so this both creates the first contact and edits it later.
  static Future<bool> save({required String name, required String phone}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await _client.from('emergency_contacts').upsert(
        {'user_id': userId, 'name': name, 'phone': phone},
        onConflict: 'user_id',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> delete() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      await _client.from('emergency_contacts').delete().eq('user_id', userId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
