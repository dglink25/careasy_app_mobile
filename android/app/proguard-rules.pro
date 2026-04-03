# Ignore les warnings SLF4J
-dontwarn org.slf4j.**
-keep class org.slf4j.** { *; }

# Firebase et FCM
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**