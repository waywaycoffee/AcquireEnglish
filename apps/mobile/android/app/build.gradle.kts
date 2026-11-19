plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.acquire.english"
    // flutter_local_notifications requires API 37+
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.acquire.english"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Sideload/release phones are overwhelmingly arm64; drop 32-bit + x86
        // to shrink fat APKs. Prefer: flutter build apk --split-per-abi.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    flavorDimensions += "env"

    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
        }
        create("prod") {
            dimension = "env"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Keep native OCR .so in the APK, but strip model assets — those are
    // downloaded on first use from https://acquireenglish.curlhairai.com/models/ocr/
    packaging {
        resources {
            excludes += setOf(
                "**/mlkit-google-ocr-models/**",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.work:work-runtime:2.11.2")
    // Bundled ML Kit API + native pipeline; model assets fetched from official CDN.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}

// AGP 8.11 cannot consume androidx.core 1.19 (needs AGP 9.1+).
configurations.configureEach {
    resolutionStrategy {
        force("androidx.core:core:1.16.0")
        force("androidx.core:core-ktx:1.16.0")
    }
}

flutter {
    source = "../.."
}
