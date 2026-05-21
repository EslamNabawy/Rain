plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun releaseProperty(name: String): String? =
    (project.findProperty(name) as String?) ?: System.getenv(name)

val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.lowercase().contains("release")
}
val releaseStoreFile = releaseProperty("RAIN_RELEASE_STORE_FILE")
val releaseStorePassword = releaseProperty("RAIN_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = releaseProperty("RAIN_RELEASE_KEY_ALIAS")
val releaseKeyPassword = releaseProperty("RAIN_RELEASE_KEY_PASSWORD")

if (isReleaseBuild) {
    require(!releaseStoreFile.isNullOrBlank()) {
        "RAIN_RELEASE_STORE_FILE is required for release signing"
    }
    require(!releaseStorePassword.isNullOrBlank()) {
        "RAIN_RELEASE_STORE_PASSWORD is required for release signing"
    }
    require(!releaseKeyAlias.isNullOrBlank()) {
        "RAIN_RELEASE_KEY_ALIAS is required for release signing"
    }
    require(!releaseKeyPassword.isNullOrBlank()) {
        "RAIN_RELEASE_KEY_PASSWORD is required for release signing"
    }
}

android {
    namespace = "com.rainapp.rain"
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
        // Keep this stable unless a package-name migration is planned.
        applicationId = "com.rainapp.rain"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile?.takeIf { it.isNotBlank() }?.let { file(it) }
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
