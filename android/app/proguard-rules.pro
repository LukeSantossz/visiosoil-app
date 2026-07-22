# TFLite Flutter plugin — keep rules for R8
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# --- Auth stack keep rules (issue #69) ---
#
# These rules are defensive. Verified by mutation (dropping the -keep line and
# rebuilding): R8 already retains the Tink and Play Services auth *classes*
# without them, because flutter_secure_storage's androidx.security-crypto
# dependency and the Play Services AAR ship their own consumer rules. They are
# kept anyway so that (a) reflectively-accessed *members* of these classes are
# not shrunk or renamed, and (b) opting into encryptedSharedPreferences or a
# future secure_storage/google_sign_in bump (#119) cannot silently reintroduce a
# release-only stripping crash. The -dontwarn lines are scoped to Tink's known
# optional compile-only references; GMS is not blanket-suppressed, so a missing
# Play Services class stays a build failure instead of a runtime NoClassDefFound.

# flutter_secure_storage's EncryptedSharedPreferences path uses Tink, which
# registers key managers via reflection R8 cannot see. Tink references these
# compile-only annotations that are not on the Android classpath.
-keep class com.google.crypto.tink.** { *; }
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**

# google_sign_in uses Google Play Services auth, partly via reflection.
-keep class com.google.android.gms.auth.** { *; }
