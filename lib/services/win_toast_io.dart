import 'dart:io';

import 'package:win_toast/win_toast.dart';

/// Windows 10+ toast via WinRT. No-op everywhere else (guarded).
Future<void> showWindowsToast({
  required String title,
  required String body,
}) async {
  if (!Platform.isWindows) return;
  try {
    await WinToast.instance().showToast(
      toast: Toast(
        duration: ToastDuration.short,
        children: [
          ToastChildVisual(
            binding: ToastVisualBinding(
              children: [
                ToastVisualBindingChildText(text: title, id: 1),
                ToastVisualBindingChildText(text: body, id: 2),
              ],
            ),
          ),
        ],
      ),
      tag: 'cubiclm',
      group: 'chat',
    );
  } catch (_) {}
}
