import 'analytics_bridge_stub.dart'
    if (dart.library.js) 'analytics_bridge_web.dart' as bridge;

/// Fires a Vercel Web Analytics custom event (see web/index.html's `va`
/// queue shim and analytics_bridge_web.dart) — aggregate usage volume
/// only, never anything tied to a specific person: an event name plus a
/// few non-identifying fields (a category, a count), never a name, email,
/// exact address, or user id. No-ops outside the web build.
void trackEvent(String name, [Map<String, Object?>? data]) {
  bridge.trackAnalyticsEvent(name, data);
}
