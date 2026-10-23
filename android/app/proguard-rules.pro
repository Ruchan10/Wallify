# MediaPipe / TFLite
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Palette
-keep class androidx.palette.** { *; }
-dontwarn androidx.palette.**

# WorkManager
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# Flutter specific. Deferred components are unused and pull in Google Play
# Core, which F-Droid's scanner rejects, so let R8 strip them.
-keep class !io.flutter.embedding.engine.deferredcomponents.**, !io.flutter.embedding.android.FlutterPlayStoreSplitApplication, io.flutter.** { *; }
-dontwarn io.flutter.**

# Keep wallpaper manager plugin
-keep class com.wallpaper_manager_flutter.** { *; }
-dontwarn com.wallpaper_manager_flutter.**

# Keep Wallify native methods
-keep class com.rk.wallify.** { *; }

# MediaPipe/TFLite transitive dependencies (annotation processing)
-dontwarn javax.annotation.processing.AbstractProcessor
-dontwarn javax.annotation.processing.SupportedAnnotationTypes
-dontwarn javax.lang.model.SourceVersion
-dontwarn javax.lang.model.element.Element
-dontwarn javax.lang.model.element.ElementKind
-dontwarn javax.lang.model.element.Modifier
-dontwarn javax.lang.model.type.TypeMirror
-dontwarn javax.lang.model.type.TypeVisitor
-dontwarn javax.lang.model.util.SimpleTypeVisitor8

# General optimizations
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification
-mergeinterfacesaggressively