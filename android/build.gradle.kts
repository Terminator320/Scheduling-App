plugins {
    // Add the dependency for the Google services Gradle plugin
    id("com.google.gms.google-services") version "4.4.4" apply false
    // Crashlytics gradle plugin — required for native-crash symbolication
    // and mapping-file upload (uploads happen automatically on assemble
    // tasks when the plugin is applied; minify settings live in app/).
    id("com.google.firebase.crashlytics") version "3.0.6" apply false
    // Performance Monitoring Gradle plugin — build-time instrumentation for
    // automatic app-start, screen-render, and HTTP/network traces.
    // (AGP version is owned by settings.gradle.kts — don't redeclare it here.)
    id("com.google.firebase.firebase-perf") version "2.0.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
