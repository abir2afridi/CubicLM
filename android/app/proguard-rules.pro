# CubicLM R8 keep rules
# Hive boxes are accessed via Map<String,dynamic> — keep Hive internals.
-keep class io.flutter.plugins.** { *; }
-keep class com.cubiclm.** { *; }

# llama.cpp / SD FFI are loaded via dart:ffi DynamicLibrary — no Java keep needed,
# but keep any Java bridge if added in future.
-keep class com.example.** { *; }

# llama_flutter_android: the native loader resolves the Kotlin progress /
# token callbacks via JNI string lookup
# (GetMethodID(..., "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;")).
# R8 must not rename or strip kotlin.jvm.functions.Function1 (or the
# synthetic lambda classes implementing it) — otherwise nativeLoadModel
# aborts the process (SIGABRT, NoSuchMethodError LK3/t;.invoke) with no
# Dart log. Only release builds minify, which is why debug never crashed.
-keep class com.write4me.llama_flutter_android.** { *; }
-keep interface kotlin.jvm.functions.Function1 { *; }
-keep class kotlin.jvm.functions.Function1 { *; }
-keepclasseswithmembernames class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}

# FlutterSecureStorage uses EncryptedSharedPreferences via reflection.
-keep class androidx.security.crypto.** { *; }

# crashlytics
-keep class com.google.firebase.crashlytics.** { *; }
-dontwarn com.google.firebase.crashlytics.**
