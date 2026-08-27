import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row from the `nearby_news` RPC (see
/// supabase/migrations/20260827120000_nearby_news_rpc.sql) — a real news
/// article G1NewsAdapter classified as a security incident, scoped to
/// whichever Brazilian state contains the query point. Unlike
/// [MapIncident], this is never rendered as a map pin: the source's own
/// precision is state-wide (see g1_news.ts's header for why), not a real
/// coordinate, so there is no [location] field to plot.
class NewsItem {
  final String id;
  final String stateCode;
  final String eventCategory;
  final String? eventType;
  final String? severity;
  final DateTime occurredAt;
  final String title;
  final String? subtitle;
  final String? articleUrl;
  final String? sourceOrganisation;

  const NewsItem({
    required this.id,
    required this.stateCode,
    required this.eventCategory,
    required this.eventType,
    required this.severity,
    required this.occurredAt,
    required this.title,
    required this.subtitle,
    required this.articleUrl,
    required this.sourceOrganisation,
  });
}

class NewsApi {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<List<NewsItem>> fetchNearby(LatLng point) async {
    try {
      final rows = await _client.rpc('nearby_news', params: {
        'point_lat': point.latitude,
        'point_lng': point.longitude,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toNewsItem)
          .whereType<NewsItem>()
          .toList();
    } catch (_) {
      // Same offline-friendly-by-design convention as every other backend
      // API here (BrazilSecurityApi, UkPoliceApi) — a failed fetch just
      // means the section renders its empty state, never an error screen.
      return [];
    }
  }

  static NewsItem? _toNewsItem(Map<String, dynamic> row) {
    final id = row['id'] as String?;
    final stateCode = row['state_code'] as String?;
    final eventCategory = row['event_category'] as String?;
    final title = row['title'] as String?;
    final occurredAtRaw = row['occurred_at'] as String?;
    final occurredAt =
        occurredAtRaw != null ? DateTime.tryParse(occurredAtRaw) : null;
    if (id == null ||
        stateCode == null ||
        eventCategory == null ||
        title == null ||
        occurredAt == null) {
      return null;
    }

    return NewsItem(
      id: id,
      stateCode: stateCode,
      eventCategory: eventCategory,
      eventType: row['event_type'] as String?,
      severity: row['severity'] as String?,
      occurredAt: occurredAt,
      title: title,
      subtitle: row['subtitle'] as String?,
      articleUrl: row['article_url'] as String?,
      sourceOrganisation: row['source_organisation'] as String?,
    );
  }
}

/// Full Portuguese name for a Brazilian UF sigla — used only to label the
/// news section by its real scope ("No noticiário — São Paulo"), never to
/// imply a precision the source doesn't have (see g1_news.ts's header).
/// Falls back to the sigla itself for anything outside Brazil's 27 UFs
/// (should never happen — nearby_news only ever returns rows whose
/// state_code came from a Brazilian security_events row).
const Map<String, String> brazilianStateNames = {
  'AC': 'Acre', 'AL': 'Alagoas', 'AP': 'Amapá', 'AM': 'Amazonas',
  'BA': 'Bahia', 'CE': 'Ceará', 'DF': 'Distrito Federal',
  'ES': 'Espírito Santo', 'GO': 'Goiás', 'MA': 'Maranhão',
  'MT': 'Mato Grosso', 'MS': 'Mato Grosso do Sul', 'MG': 'Minas Gerais',
  'PA': 'Pará', 'PB': 'Paraíba', 'PR': 'Paraná', 'PE': 'Pernambuco',
  'PI': 'Piauí', 'RJ': 'Rio de Janeiro', 'RN': 'Rio Grande do Norte',
  'RS': 'Rio Grande do Sul', 'RO': 'Rondônia', 'RR': 'Roraima',
  'SC': 'Santa Catarina', 'SP': 'São Paulo', 'SE': 'Sergipe',
  'TO': 'Tocantins',
};
