import java.util.Properties
import java.io.FileInputStream
import java.io.File

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

// media_kit 1.2.6 has an Android release-only disposal race on Flutter 3.38+:
// it closes NativeCallable, then waits 5 seconds before joining mpv's thread.
// An in-flight callback in that window aborts the process. This applies the
// upstream fix (media-kit/media-kit#1424) until pub.dev contains it.
val patchMediaKitDisposeRace = tasks.register("patchMediaKitDisposeRace") {
    doLast {
        val pubCache = System.getenv("PUB_CACHE")?.let(::File)
            ?: File(System.getProperty("user.home"), ".pub-cache")
        val packageDir = File(pubCache, "hosted/pub.dev/media_kit-1.2.6")
        require(packageDir.isDirectory) {
            "media_kit 1.2.6 is missing from $packageDir; run flutter pub get first."
        }

        fun patch(relative: String, old: String, replacement: String) {
            val target = File(packageDir, relative)
            val source = target.readText()
            val marker = replacement.lineSequence()
                .first { it.isNotBlank() }
                .trim()
            if (source.lineSequence().any { it.trim() == marker }) return
            require(source.contains(old)) {
                "media_kit source changed; refuse to apply stale crash patch to $target"
            }
            target.writeText(source.replace(old, replacement))
        }

        patch(
            "lib/src/player/native/core/initializer_native_callable.dart",
            """
  void dispose(Pointer<generated.mpv_handle> ctx) {
    _locks.remove(ctx.address);
    _eventCallbacks.remove(ctx.address);

    // Clear the wakeup callback in libmpv before closing NativeCallable
    // to prevent libmpv from invoking a deleted callback
    mpv.mpv_set_wakeup_callback(ctx, nullptr, nullptr);
    
    _wakeUpNativeCallables.remove(ctx.address)?.close();
  }
""".trimIndent(),
            """
  WakeUpNativeCallable? dispose(Pointer<generated.mpv_handle> ctx) {
    _locks.remove(ctx.address);
    _eventCallbacks.remove(ctx.address);

    // Stop new wakeups, but keep the callable alive until mpv's thread joins.
    mpv.mpv_set_wakeup_callback(ctx, nullptr, nullptr);
    return _wakeUpNativeCallables.remove(ctx.address);
  }
""".trimIndent(),
        )
        patch(
            "lib/src/player/native/core/initializer.dart",
            """
  void dispose(Pointer<generated.mpv_handle> ctx) {
    if (!isExecmemRestricted) {
      InitializerNativeCallable(mpv).dispose(ctx);
    } else {
      InitializerIsolate().dispose(mpv, ctx);
    }
  }
""".trimIndent(),
            """
  WakeUpNativeCallable? dispose(Pointer<generated.mpv_handle> ctx) {
    if (!isExecmemRestricted) {
      return InitializerNativeCallable(mpv).dispose(ctx);
    } else {
      InitializerIsolate().dispose(mpv, ctx);
      return null;
    }
  }
""".trimIndent(),
        )
        patch(
            "lib/src/player/native/player/real.dart",
            """
      Initializer(mpv).dispose(ctx);

      Future.delayed(const Duration(seconds: 5), () {
        mpv.mpv_terminate_destroy(ctx);
      });
""".trimIndent(),
            """
      final callable = Initializer(mpv).dispose(ctx);

      Future.delayed(const Duration(seconds: 5), () {
        mpv.mpv_terminate_destroy(ctx);
        callable?.close();
      });
""".trimIndent(),
        )
    }
}

tasks.configureEach {
    if (name.startsWith("compileFlutterBuild")) {
        dependsOn(patchMediaKitDisposeRace)
    }
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
                // Some OEM package installers (and Edge/sideload parsers) still
                // require JAR v1 META-INF certs; v2-only APKs show
                // "parser did not find any certificates".
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
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
