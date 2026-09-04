/// Non-web platforms have no `window.va` to call into — every BeeAware
/// build target other than the web one (this app is web-only today, but
/// mirrors the pwa_bridge_stub/_web split in case that changes) just
/// no-ops here instead of the real implementation in
/// analytics_bridge_web.dart.
void trackAnalyticsEvent(String name, [Map<String, Object?>? data]) {}
