import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.acquire.english"
    // flutter_local_notifications requires API 37+
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.acquire.english"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Sideload/release phones are overwhelmingly arm64. Also pass
        // --target-platform android-arm64 when building the website APK.
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a"))
        }
    }

    signingConfigs {
        // Shared team debug cert — must match sideload devices (SHA256 2D:79:38:C4:…).
        // Place file at android/keystore/team-debug.keystore (gitignored).
        // Do not fall back to ~/.android/debug.keystore (machine-local certs diverge).
        getByName("debug") {
            val teamDebugKeystore = rootProject.file("keystore/team-debug.keystore")
            require(teamDebugKeystore.isFile) {
                "Missing $teamDebugKeystore — copy the team debug keystore before building."
            }
            storeFile = teamDebugKeystore
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
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
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // ML Kit keep rules live in proguard-rules.pro — validate on device
            // after every minify-on release (cold-start MlKitInitProvider).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Keep native OCR .so for arm64 only. Model assets under
    // mlkit-google-ocr-models are fetched on first use from ECS CDN.
    packaging {
        jniLibs {
            excludes += setOf(
                "**/armeabi/**",
                "**/armeabi-v7a/**",
                "**/x86/**",
                "**/x86_64/**",
                "**/mips/**",
                "**/mips64/**",
            )
        }
        resources {
            excludes += setOf(
                "**/mlkit-google-ocr-models/**",
                "**/META-INF/*.kotlin_module",
                "**/META-INF/AL2.0",
                "**/META-INF/LGPL2.1",
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

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
