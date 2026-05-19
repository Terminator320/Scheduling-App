plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")

    // Add the Google services Gradle plugin
    id("com.google.gms.google-services")
    // Crashlytics gradle plugin — uploads mapping files and the NDK
    // symbols bundle on release assemble tasks, so native + obfuscated
    // stack traces symbolicate in the Firebase Crashlytics console.
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.example.scheduling"
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
        applicationId = "com.example.scheduling"
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

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.10.0"))

    // Firebase Crashlytics — native crash reporting + mapping-file
    // uploads. The Dart-side firebase_crashlytics plugin still owns
    // Flutter error capture (see FlutterError.onError wiring in main.dart);
    // this dep is what makes Android native (JNI/NDK) crashes surface
    // and produces symbolicated R8 stack traces in the Firebase console.
    implementation("com.google.firebase:firebase-crashlytics")
}
