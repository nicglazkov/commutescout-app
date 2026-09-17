# Ferrostar's Rust bindings are reached through JNA; keep the generated types.
-keep class uniffi.ferrostar.** { *; }
-keep class com.sun.jna.** { *; }
-dontwarn java.awt.**
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
# kotlinx.serialization models
-keep,includedescriptorclasses class com.commutescout.drive.**$$serializer { *; }
-keepclassmembers class com.commutescout.drive.** { *** Companion; }
-keepclasseswithmembers class com.commutescout.drive.** { kotlinx.serialization.KSerializer serializer(...); }
