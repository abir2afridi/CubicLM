// Web Notification API facade — other platforms use their own plugins.
export 'web_notify_stub.dart'
    if (dart.library.html) 'web_notify_web.dart';
