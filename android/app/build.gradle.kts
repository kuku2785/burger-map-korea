import java.util.Base64
import org.gradle.api.tasks.Sync

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun findDartDefine(defines: String, key: String): String {
    return defines
        .split(",")
        .mapNotNull { encoded ->
            runCatching { String(Base64.getDecoder().decode(encoded)) }.getOrNull()
        }
        .firstOrNull { decoded -> decoded.startsWith("$key=") }
        ?.substringAfter("=")
        ?: ""
}

val localStagingAsset =
    rootProject.file("../assets/dev/yongsan_burger_stores_staging.json")
val generatedDebugAssetsDirectory =
    layout.buildDirectory.dir("generated/debugStagingAssets")
val prepareDebugStagingAssets by tasks.registering(Sync::class) {
    from(localStagingAsset) {
        into("flutter_assets/assets/dev")
    }
    into(generatedDebugAssetsDirectory)
}

android {
    namespace = "com.burgermap.burger_map_korea"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.burgermap.burger_map_korea"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] =
            providers.gradleProperty("GOOGLE_MAPS_API_KEY")
                .orElse(providers.environmentVariable("GOOGLE_MAPS_API_KEY"))
                .orElse(
                    providers.gradleProperty("dart-defines").map { defines ->
                        findDartDefine(defines, "GOOGLE_MAPS_API_KEY")
                    }
                )
                .orElse("")
                .get()
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("debug").assets.srcDir(generatedDebugAssetsDirectory.get().asFile)
    }
}

tasks.matching { it.name == "mergeDebugAssets" }.configureEach {
    dependsOn(prepareDebugStagingAssets)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
