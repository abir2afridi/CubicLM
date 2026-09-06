// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// Browser Notification API (permission may require a prior user gesture;
/// failure just returns false — best effort by design).
Future<bool> showWebNotification({
  required String title,
  required String body,
}) async {
  try {
    var permission = html.Notification.permission;
    if (permission != 'granted') {
      permission = await html.Notification.requestPermission();
    }
    if (permission != 'granted') return false;
    html.Notification(title, body: body);
    return true;
  } catch (_) {
    return false;
  }
}
