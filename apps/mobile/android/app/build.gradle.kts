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

val legacyKeystoreProperties = Properties()
val legacyKeystorePropertiesFile = rootProject.file("key-legacy.properties")
if (legacyKeystorePropertiesFile.exists()) {
    legacyKeystoreProperties.load(FileInputStream(legacyKeystorePropertiesFile))
}

// media_kit 1.2.6 has an Android release-only disposal race on Flutter 3.38+:
// it closes NativeCallable, then waits 5 seconds before joining mpv's thread.
// An in-flight callback in that window aborts the process. This applies the
// upstream fix (media-kit/media-kit#1424) until pub.dev contains it.
val patchMediaKitDisposeRace = tasks.register("patchMediaKitDisposeRace") {
    doLast {
        val pubCache = System.getenv("PUB_CACHE")?.let(::File)
            ?: File(System.getProperty("user.home"), ".pub-cache")
        val packageDirs = listOf(
            File(pubCache, "hosted/pub.dev/media_kit-1.2.6"),
            File(pubCache, "hosted/pub.flutter-io.cn/media_kit-1.2.6"),
        ).filter { it.isDirectory }
        require(packageDirs.isNotEmpty()) {
            "media_kit 1.2.6 is missing under $pubCache/hosted; run flutter pub get first."
        }

        fun patch(packageDir: File, relative: String, old: String, replacement: String) {
            val target = File(packageDir, relative)
            val source = target.readText()
            val marker = replacement.lineSequence()
                .first { it.isNotBlank() }
                .trim()
            if (source.lineSequence().any { it.trim() == marker }) return
            // pub.dev may keep trailing spaces / CRLF; normalize before match.
            fun normalize(text: String): String =
                text.replace("\r\n", "\n")
                    .replace("\r", "\n")
                    .lineSequence()
                    .joinToString("\n") { it.trimEnd() }
            val normalizedSource = normalize(source)
            val normalizedOld = normalize(old)
            require(normalizedSource.contains(normalizedOld)) {
                "media_kit source changed; refuse to apply stale crash patch to $target"
            }
            target.writeText(
                normalizedSource.replace(normalizedOld, normalize(replacement)),
            )
        }

        // Keep Dart indentation exact — do not use trimIndent() (it eats the
        // method-level indent and then fails to match pub.dev sources).
        for (packageDir in packageDirs) {
            patch(
                packageDir,
                "lib/src/player/native/core/initializer_native_callable.dart",
                listOf(
                    "  void dispose(Pointer<generated.mpv_handle> ctx) {",
                    "    _locks.remove(ctx.address);",
                    "    _eventCallbacks.remove(ctx.address);",
                    "",
                    "    // Clear the wakeup callback in libmpv before closing NativeCallable",
                    "    // to prevent libmpv from invoking a deleted callback",
                    "    mpv.mpv_set_wakeup_callback(ctx, nullptr, nullptr);",
                    "",
                    "    _wakeUpNativeCallables.remove(ctx.address)?.close();",
                    "  }",
                ).joinToString("\n"),
                listOf(
                    "  WakeUpNativeCallable? dispose(Pointer<generated.mpv_handle> ctx) {",
                    "    _locks.remove(ctx.address);",
                    "    _eventCallbacks.remove(ctx.address);",
                    "",
                    "    // Stop new wakeups, but keep the callable alive until mpv's thread joins.",
                    "    mpv.mpv_set_wakeup_callback(ctx, nullptr, nullptr);",
                    "    return _wakeUpNativeCallables.remove(ctx.address);",
                    "  }",
                ).joinToString("\n"),
            )
            patch(
                packageDir,
                "lib/src/player/native/core/initializer.dart",
                listOf(
                    "  void dispose(Pointer<generated.mpv_handle> ctx) {",
                    "    if (!isExecmemRestricted) {",
                    "      InitializerNativeCallable(mpv).dispose(ctx);",
                    "    } else {",
                    "      InitializerIsolate().dispose(mpv, ctx);",
                    "    }",
                    "  }",
                ).joinToString("\n"),
                listOf(
                    "  WakeUpNativeCallable? dispose(Pointer<generated.mpv_handle> ctx) {",
                    "    if (!isExecmemRestricted) {",
                    "      return InitializerNativeCallable(mpv).dispose(ctx);",
                    "    } else {",
                    "      InitializerIsolate().dispose(mpv, ctx);",
                    "      return null;",
                    "    }",
                    "  }",
                ).joinToString("\n"),
            )
            patch(
                packageDir,
                "lib/src/player/native/player/real.dart",
                listOf(
                    "      Initializer(mpv).dispose(ctx);",
                    "",
                    "      Future.delayed(const Duration(seconds: 5), () {",
                    "        mpv.mpv_terminate_destroy(ctx);",
                    "      });",
                ).joinToString("\n"),
                listOf(
                    "      final callable = Initializer(mpv).dispose(ctx);",
                    "",
                    "      Future.delayed(const Duration(seconds: 5), () {",
                    "        mpv.mpv_terminate_destroy(ctx);",
                    "        callable?.close();",
                    "      });",
                ).joinToString("\n"),
            )
        }
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
            require(keystorePropertiesFile.isFile) {
                "Missing $keystorePropertiesFile — copy release key.properties before building."
            }
            val releaseStore = rootProject.file(keystoreProperties["storeFile"] as String)
            require(releaseStore.isFile) {
                "Missing $releaseStore — copy acquireenglish-upload.jks before building."
            }
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = releaseStore
            storePassword = keystoreProperties["storePassword"] as String
            // Some OEM package installers (and Edge/sideload parsers) still
            // require JAR v1 META-INF certs; v2-only APKs show
            // "parser did not find any certificates".
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
        // Side-by-side compare / pre-redesign rollback install.
        // Different cert + applicationIdSuffix=.legacy so it can sit next to prod.
        create("legacy") {
            require(legacyKeystorePropertiesFile.isFile) {
                "Missing $legacyKeystorePropertiesFile — copy key-legacy.properties before building legacy."
            }
            val legacyStore = rootProject.file(legacyKeystoreProperties["storeFile"] as String)
            require(legacyStore.isFile) {
                "Missing $legacyStore — generate acquireenglish-legacy.jks before building legacy."
            }
            keyAlias = legacyKeystoreProperties["keyAlias"] as String
            keyPassword = legacyKeystoreProperties["keyPassword"] as String
            storeFile = legacyStore
            storePassword = legacyKeystoreProperties["storePassword"] as String
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
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
        // Dual-install compare slot: com.acquire.english.legacy
        // Launcher name: 爱快英语·旧版. Does not overwrite prod data.
        create("legacy") {
            dimension = "env"
            applicationIdSuffix = ".legacy"
            versionNameSuffix = "-legacy"
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            // Flutter `assembleLegacyRelease` → legacy compare cert;
            // all other release flavors → upload/prod cert.
            val assemblingLegacy =
                gradle.startParameter.taskNames.any {
                    it.contains("Legacy", ignoreCase = true)
                }
            signingConfig =
                if (assemblingLegacy) {
                    signingConfigs.getByName("legacy")
                } else {
                    signingConfigs.getByName("release")
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
