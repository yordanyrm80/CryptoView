plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yordany.cryptoview"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yordany.cryptoview"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

tasks.configureEach {
    if (name == "assembleRelease") {
        doLast {
            val apkReleaseDir = layout.buildDirectory.dir("outputs/apk/release").get().asFile
            val flutterApkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
            val sourceApk = listOf(
                File(flutterApkDir, "app-release.apk"),
                File(apkReleaseDir, "app-release.apk"),
            ).firstOrNull { it.exists() }
            if (sourceApk != null) {
                flutterApkDir.mkdirs()
                val vName = android.defaultConfig.versionName ?: "1.0.0"
                val vCode = android.defaultConfig.versionCode ?: 1
                val brandedApk = File(flutterApkDir, "CryptoView-v${vName}-b${vCode}-release.apk")
                sourceApk.copyTo(brandedApk, overwrite = true)
                println("Branded APK created: ${brandedApk.absolutePath}")
            }
        }
    }
}
