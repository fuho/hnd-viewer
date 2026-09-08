plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hndviewer.hnd_viewer"
    compileSdk = flutter.compileSdkVersion
    // Pin to the NDK already installed on this machine (Flutter's default
    // 28.2 is not present and cannot be auto-downloaded here).
    ndkVersion = "30.0.14904198"
    // Pin to the installed build-tools (Flutter's default 36.0.0 is absent).
    buildToolsVersion = "37.0.0"

    // Use a workspace-local debug keystore (the default ~/.android one is not
    // writable in this environment).
    signingConfigs {
        getByName("debug") {
            storeFile = file("../debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hndviewer.hnd_viewer"
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

    buildTypes {
        release {
            // Signing with the committed android/debug.keystore (the well-known
            // public "androiddebugkey" credential, not a secret) for now. This
            // is fine for an initial open release: CI (see
            // .github/workflows/release.yml) builds signed artifacts with no
            // secrets configured because the keystore ships in the repo.
            // TODO: For a production release, add a real keystore (e.g. from
            // the ANDROID_KEYSTORE_* GitHub secrets) and a release signingConfig
            // that reads it, then point this buildType at that config.
            signingConfig = signingConfigs.getByName("debug")
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
