// Windows toast facade — web builds pick the no-op stub.
export 'win_toast_stub.dart' if (dart.library.io) 'win_toast_io.dart';
