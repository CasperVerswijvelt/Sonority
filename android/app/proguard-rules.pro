# R8 keep rules for the release build (isMinifyEnabled + isShrinkResources).
# Only for classes R8 can't see are reachable — reflection, manifest, and
# platform-channel entry points. Add a rule only when a release build actually
# strips something; don't pre-add speculative keeps.

# Flutter engine + embedding (defensive; the Flutter Gradle plugin covers most).
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Our manifest-referenced components (AAPT keeps these, but be explicit): the
# Flutter host, the app-widget provider, and the widget-config activity — all
# instantiated by the framework by name, not from Dart/Kotlin call sites.
-keep class be.casperverswijvelt.sonority.** { *; }

# home_widget: uses RemoteViews/reflection to drive the home-screen widget.
-keep class es.antonborri.home_widget.** { *; }
-dontwarn es.antonborri.home_widget.**
