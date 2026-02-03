import 'package:latlong2/latlong.dart';

enum IncidentSeverity {
  low,
  medium,
  high,
}

class MapIncident {
  final String id;
  final LatLng location;
  final IncidentSeverity severity;
  final String category;
  final String subcategory;
  final String description;
  final DateTime dateTime;

  final bool isPending;
  final DateTime? visibleAt;

  // 🔐 anti-abuso
  final String? hash;

  // 🆕 origem do dado
  final bool isOfficial;

  MapIncident({
    required this.id,
    required this.location,
    required this.severity,
    required this.category,
    required this.subcategory,
    required this.description,
    required this.dateTime,
    this.isPending = false,
    this.visibleAt,
    this.hash,
    this.isOfficial = false, // ✅ default seguro
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lat': location.latitude,
      'lng': location.longitude,
      'severity': severity.name,
      'category': category,
      'subcategory': subcategory,
      'description': description,
      'date_time': dateTime.toIso8601String(),
      'is_pending': isPending,
      'visible_at': visibleAt?.toIso8601String(),
      'hash': hash,
      'is_official': isOfficial, // ✅ único campo de origem
    };
  }

  factory MapIncident.fromJson(Map<String, dynamic> json) {
    // 🔄 compatibilidade com versões antigas
    final legacySource = json['source'] as String?;

    return MapIncident(
      id: json['id'] as String,
      location: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      severity: IncidentSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => IncidentSeverity.low,
      ),
      category: json['category'] as String,
      subcategory: json['subcategory'] as String,
      description: json['description'] as String,
      dateTime: DateTime.parse(json['date_time']),
      isPending: json['is_pending'] == true,
      visibleAt: json['visible_at'] != null
          ? DateTime.parse(json['visible_at'])
          : null,
      hash: json['hash'] as String?,
      isOfficial: json['is_official'] == true ||
          legacySource == 'official', // ✅ fallback seguro
    );
  }

  factory MapIncident.fromSupabase(Map<String, dynamic> row) {
    return MapIncident(
      id: row['id'].toString(),
      location: LatLng(
        (row['lat'] as num).toDouble(),
        (row['lng'] as num).toDouble(),
      ),
      severity: IncidentSeverity.values.firstWhere(
        (e) => e.name == row['severity'],
        orElse: () => IncidentSeverity.low,
      ),
      category: row['category'],
      subcategory: row['subcategory'],
      description: row['description'] ?? '',
      dateTime: DateTime.parse(row['created_at']),
      visibleAt:
          row['visible_at'] != null ? DateTime.parse(row['visible_at']) : null,
      hash: row['hash_fingerprint'],
      isOfficial: row['is_official'] == true, // ✅ Supabase manda a verdade
    );
  }
}
