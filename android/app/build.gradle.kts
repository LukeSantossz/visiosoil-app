import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is sourced from an untracked android/key.properties, so no
// keystore or password is committed. When the file is absent (contributors, CI),
// the release APK falls back to the debug key with a warning so it still runs.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// The bundle's only consumer is Play, which rejects the debug key, so the
// fallback above stops at the APK: bundleRelease refuses it before any task
// runs, unless CI names the opt-out to prove the bundle builds (SPEC 0111).
val allowDebugBundle = System.getenv("VISIOSOIL_ALLOW_DEBUG_BUNDLE") == "true"
if (!hasReleaseKeystore && !allowDebugBundle) {
    gradle.taskGraph.whenReady {
        if (allTasks.any { it.name == "bundleRelease" }) {
            throw GradleException(
                "android/key.properties not found; refusing to sign the release app bundle " +
                    "with the debug key, which Play rejects. Create it as the README's " +
                    "Release Signing section shows, or set VISIOSOIL_ALLOW_DEBUG_BUNDLE=true " +
                    "to build a bundle that only proves it builds."
            )
        }
    }
}

android {
    namespace = "com.visiosoil.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Permanent from the first Play upload: a different id is a different app
        // (#267, SPEC 0088).
        applicationId = "com.visiosoil.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sign with the untracked release keystore when present; otherwise
            // fall back to the debug key so contributors and CI can still build.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "WARNING: android/key.properties not found; " +
                        "signing the release build with the debug key."
                )
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
