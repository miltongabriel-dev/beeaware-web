class AppConfig {
  /// Delay before an incident becomes visible on the map
  static const Duration incidentVisibilityDelay = Duration(minutes: 1); // dev

  // Em produção, será:
  // static const Duration incidentVisibilityDelay = Duration(minutes: 5);
}
