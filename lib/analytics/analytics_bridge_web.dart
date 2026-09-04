import 'dart:js' as js;

/// Real web implementation — `window.va` is the queue shim web/index.html
/// sets up before Vercel's Web Analytics script tag (same file also
/// explains why this isn't the @vercel/analytics npm package: this is a
/// Flutter build, not Node/React). Calling window.va works immediately,
/// even before the real script has finished loading — the shim just
/// pushes onto window.vaq until the script processes the queue, so there
/// is nothing here to await or race against.
void trackAnalyticsEvent(String name, [Map<String, Object?>? data]) {
  try {
    if (!js.context.hasProperty('va')) return;
    final payload = <String, Object?>{'name': name};
    if (data != null && data.isNotEmpty) payload['data'] = data;
    js.context.callMethod('va', ['event', js.JsObject.jsify(payload)]);
  } catch (_) {}
}
