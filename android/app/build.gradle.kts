// android/app/build.gradle.kts
//
// App-level Gradle build script with:
//   • Chaquopy plugin for offline Python 3.10 execution
//   • CPU ABI filters: armeabi-v7a, arm64-v8a, x86_64
//   • minSdk bumped to 24 (Chaquopy 16 requirement)
//   • INTERNET permission for WebView data-URI loads (not required, but avoids
//     "net::ERR_UNKNOWN_URL_SCHEME" on certain OEM builds when using loadData)

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Apply Chaquopy AFTER the Android plugin (order is mandatory).
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied last.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Third-party runtime dependencies ─────────────────────────────────────────
dependencies {
    // MediaPipe LLM Inference API for on-device AI tutoring.
    // Provides LlmInference which wraps GPU-accelerated token generation.
    implementation("com.google.mediapipe:tasks-genai:0.10.27")
}


android {
    namespace = "com.example.ethiocode"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.ethiocode"

        // Chaquopy 16+ requires minSdk ≥ 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── ABI filters – target low/mid-range Android devices ─────────────
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            // Use debug signing for now; replace with keystore for production.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            isDebuggable = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// ── Chaquopy DSL block (top-level, outside android{}) ─────────────────────────
// Matches the standard recommended position for Chaquopy ≥ 16 Kotlin DSL.
chaquopy {
    defaultConfig {
        // Mirror the version declared above.
        version = "3.10"
    }
    // Per-ABI overrides can be added here if needed, e.g.:
    // productFlavors { }
}

flutter {
    source = "../.."
}
