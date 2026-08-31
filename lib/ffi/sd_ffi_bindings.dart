// Conditional export — io (mobile/desktop) vs web stub.
export 'sd_ffi_bindings_io.dart' if (dart.library.html) 'sd_ffi_bindings_web.dart';
