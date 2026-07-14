import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Reads android/key.properties for local builds; falls back to
// ANDROID_* environment variables in CI. If neither provides a real keystore the
// release build uses the debug key, so `flutter run --release` and the sideload
// APK still build without any secrets.
val keystoreProperties = Properties()
rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use {
    keystoreProperties.load(it)
}
fun signingProp(propKey: String, envKey: String): String? {
    val v = keystoreProperties.getProperty(propKey) ?: System.getenv(envKey)
    return if (v.isNullOrBlank()) null else v
}
val releaseStoreFile = signingProp("storeFile", "ANDROID_KEYSTORE_PATH")
val hasReleaseSigning = releaseStoreFile != null && file(releaseStoreFile).exists()

android {
    namespace = "be.casperverswijvelt.sonority"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "be.casperverswijvelt.sonority"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(releaseStoreFile!!)
                storePassword = signingProp("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingProp("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingProp("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Upload key when configured (key.properties locally / env vars in
            // CI), otherwise debug so unsigned builds still work.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 code + resource shrinking (Play Console "technical quality"
            // recommendation). Keep rules for reflection/channel paths live in
            // proguard-rules.pro. Smoke-test a real release build on device when
            // touching these — R8 can strip classes analyze/test never exercise.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// AGP 9 (android.newDsl=true) drops the old kotlinOptions block; the Kotlin
// jvmTarget now lives in the top-level compilerOptions DSL.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
