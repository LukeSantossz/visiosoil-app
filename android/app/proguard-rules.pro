# --- Auth stack keep rules (issue #69) ---
#
# These rules are defensive. Verified by mutation on flutter_secure_storage 9
# (dropping the -keep line and rebuilding): R8 retained the Tink and Play
# Services auth *classes* without them, through the consumer rules of
# androidx.security-crypto and the Play Services AAR. They are kept so that
# (a) reflectively-accessed *members* of these classes are not shrunk or
# renamed, and (b) a future secure_storage/google_sign_in bump (#119) cannot
# silently reintroduce a release-only stripping crash. The -dontwarn lines are
# scoped to Tink's known optional compile-only references; GMS is not
# blanket-suppressed, so a missing Play Services class stays a build failure
# instead of a runtime NoClassDefFound.

# Tink registers key managers via reflection R8 cannot see, and references these
# compile-only annotations that are not on the Android classpath. Since
# flutter_secure_storage 11 (SPEC 0159), the plugin still declares tink-android
# but its code no longer calls it, so this rule is what keeps Tink in the APK.
-keep class com.google.crypto.tink.** { *; }
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**

# google_sign_in uses Google Play Services auth, partly via reflection.
-keep class com.google.android.gms.auth.** { *; }
