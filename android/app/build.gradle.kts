import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")

    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")

    // Add the Google services Gradle plugin
    id("com.google.gms.google-services")
    // Crashlytics gradle plugin — uploads mapping files and the NDK
    // symbols bundle on release assemble tasks, so native + obfuscated
    // stack traces symbolicate in the Firebase Crashlytics console.
    id("com.google.firebase.crashlytics")
    // Performance Monitoring Gradle plugin
    id("com.google.firebase.firebase-perf")
}

val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()

if (agpMajor < 9) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

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


    defaultConfig {
        applicationId = "net.vogas.scheduling"

        minSdk = maxOf(flutter.minSdkVersion, 23)
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

            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}


project.extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java) {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.14.0"))

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

    // Performance Monitoring library — version managed by the BoM above.
    // Automatic traces only (app start, screen rendering, network requests):
    // this native dep + the firebase-perf Gradle plugin provide them with no
    // Dart-side plugin. The Dart firebase_performance package was removed —
    // the app defines no custom traces.
    implementation("com.google.firebase:firebase-perf")
}
