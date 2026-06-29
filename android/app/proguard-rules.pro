# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Google Maps
-keep class com.google.maps.** { *; }
-keep class com.google.android.libraries.maps.** { *; }

# Google Sign In
-keep class com.google.android.gms.auth.** { *; }

# MobiGas models - keep all model classes
-keep class com.mobigas.mobigas.** { *; }

# Keep Dart entry points
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

# Remove debug logs in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
