/// No-op stub for non-web platforms.
Future<bool> showWebNotification({
  required String title,
  required String body,
}) async =>
    false;
