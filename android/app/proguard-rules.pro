# CubicLM R8 keep rules
# Hive boxes are accessed via Map<String,dynamic> — keep Hive internals.
-keep class io.flutter.plugins.** { *; }
-keep class com.cubiclm.** { *; }

# llama.cpp / SD FFI are loaded via dart:ffi DynamicLibrary — no Java keep needed,
# but keep any Java bridge if added in future.
-keep class com.example.** { *; }

# FlutterSecureStorage uses EncryptedSharedPreferences via reflection.
-keep class androidx.security.crypto.** { *; }

# crashlytics
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**
