plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.secretarrow.zagents"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.secretarrow.zagents"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Signing material is injected via environment variables by
            // .github/workflows/release.yml (unzipped from the AES-256 encrypted
            // key-sign-apk.zip stored in this repository; the password lives in
            // the KEYSTORE_PASSWORD Actions secret and is never committed).
            val ksPath = System.getenv("KEYSTORE_PATH")
            val storePass = System.getenv("KEYSTORE_STORE_PASSWORD")
                ?: System.getenv("KEYSTORE_PASSWORD")
            val keyPass = System.getenv("KEYSTORE_KEY_PASSWORD") ?: storePass
            if (!ksPath.isNullOrBlank() && !storePass.isNullOrBlank()) {
                storeFile = file(ksPath)
                storePassword = storePass
                keyAlias = System.getenv("KEYSTORE_ALIAS") ?: "zagents"
                keyPassword = keyPass
            }
        }
    }

    buildTypes {
        release {
            val releaseSigningConfigured = !System.getenv("KEYSTORE_PATH").isNullOrBlank() &&
                !(System.getenv("KEYSTORE_STORE_PASSWORD") ?: System.getenv("KEYSTORE_PASSWORD")).isNullOrBlank()
            // The release workflow sets ZAGENTS_REQUIRE_SIGNING=true: publishing a
            // debug-signed APK is worse than failing the build.
            val requireSigning = System.getenv("ZAGENTS_REQUIRE_SIGNING") == "true"
            if (requireSigning && !releaseSigningConfigured) {
                throw GradleException(
                    "Release signing is required (ZAGENTS_REQUIRE_SIGNING=true) but " +
                        "KEYSTORE_PATH / KEYSTORE_STORE_PASSWORD are missing.",
                )
            }
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("release")
            } else {
                // Without a keystore (local dev / forks) fall back to debug keys
                // so `flutter run --release` keeps working.
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
