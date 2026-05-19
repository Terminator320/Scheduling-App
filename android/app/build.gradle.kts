import java.util.Properties
import java.io.FileInputStream

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

// C2: release signing reads from android/key.properties when present.
// If the file is absent (dev machines that haven't generated a keystore),
// release builds fall back to the debug keystore — `flutter run --release`
// keeps working. See HANDOFF.md for the keytool command + backup procedure.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    keystoreProperties.getProperty("storeFile")?.isNotBlank() == true

android {
    namespace = "net.vogas.scheduling"
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
        applicationId = "net.vogas.scheduling"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // C2: use real signing config when key.properties is present;
            // fall back to debug keystore so dev `flutter run --release` works.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // C3: R8 + resource shrinking. Keep rules in proguard-rules.pro
            // cover Firebase, Crashlytics, image_picker, flutter_image_compress,
            // and Kotlin reflection — anything reached via reflection that R8
            // can't trace from a call site.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

    // Firebase Analytics — auto-collects first_open, screen_view (when the
    // Dart firebase_analytics plugin is added), session start, in-app
    // purchase events. Crashlytics also uses Analytics for user attribution
    // on crash events, so keeping it present improves Crashlytics fidelity
    // even without explicit Dart-side tracking.
    implementation("com.google.firebase:firebase-analytics")
}
