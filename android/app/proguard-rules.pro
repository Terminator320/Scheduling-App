# C3 — R8 keep rules for the Scheduling App release build.
#
# Flutter itself ships an aggregated rules file (the gradle plugin pulls
# in plugin-specific rules from each Flutter package), so we only list
# entries here that we know R8 needs and that aren't covered upstream.
# When something breaks in release after a dep bump, add it here rather
# than disabling minify.

# ---- Flutter framework ----
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ---- Firebase + Google Play services ----
# BoM-managed deps in use: firebase-app-check, firebase-auth,
# firebase-firestore, firebase-storage, firebase-functions,
# firebase-crashlytics, firebase-messaging (transitive).
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics needs the line number table preserved so symbolicated
# stack traces from the uploaded mapping file are useful.
-keepattributes SourceFile,LineNumberTable
-keep class com.google.firebase.crashlytics.** { *; }

# ---- Plugins that use reflection / JNI ----
# image_picker — Android Activity result types
-keep class io.flutter.plugins.imagepicker.** { *; }

# flutter_image_compress — native bridge in the plugin
-keep class com.fluttercandies.image_compress.** { *; }

# ---- Kotlin reflection (used by Firebase + some Flutter plugins) ----
-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.** { *; }
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations
-keepattributes AnnotationDefault
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ---- Suppress noisy warnings for optional deps ----
# javax.annotation pulled in by gRPC (Firestore transport) but not used.
-dontwarn javax.annotation.**
# OkHttp's optional Conscrypt + BouncyCastle paths.
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
# Flutter framework references Google Play Core's split-install API for
# deferred components / dynamic feature modules. We don't use those, so the
# code path is dead — tell R8 to stop failing on the missing classes instead
# of adding the unused com.google.android.play:feature-delivery dep.
-dontwarn com.google.android.play.core.**
