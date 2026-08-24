import java.util.Base64
import java.util.Properties
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

val releaseBuildRequested =
    gradle.startParameter.taskNames.any { taskName ->
        taskName.substringAfterLast(":").contains("release", ignoreCase = true)
    }
val releaseSigningPropertyNames =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val releaseSigningProperties = Properties()
var releaseKeystoreFile: File? = null

if (releaseBuildRequested) {
    val keyPropertiesFile = rootProject.file("key.properties")
    if (!keyPropertiesFile.isFile) {
        throw GradleException(
            "Release signing configuration is missing: android/key.properties"
        )
    }

    keyPropertiesFile.inputStream().use(releaseSigningProperties::load)
    val invalidProperties =
        releaseSigningPropertyNames.filter { propertyName ->
            val value = releaseSigningProperties.getProperty(propertyName)?.trim().orEmpty()
            value.isEmpty() || value.contains("REPLACE", ignoreCase = true)
        }
    if (invalidProperties.isNotEmpty()) {
        throw GradleException(
            "Release signing properties are missing or placeholders: " +
                invalidProperties.sorted().joinToString(", ")
        )
    }

    val resolvedKeystoreFile =
        file(releaseSigningProperties.getProperty("storeFile").trim())
    if (!resolvedKeystoreFile.isFile) {
        throw GradleException(
            "Release signing keystore is missing for property: storeFile"
        )
    }
    releaseKeystoreFile = resolvedKeystoreFile
}

android {
    namespace = "com.burgermapkorea.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.burgermapkorea.app"
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

    signingConfigs {
        if (releaseBuildRequested) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = releaseSigningProperties.getProperty("storePassword").trim()
                keyAlias = releaseSigningProperties.getProperty("keyAlias").trim()
                keyPassword = releaseSigningProperties.getProperty("keyPassword").trim()
            }
        }
    }

    buildTypes {
        release {
            if (releaseBuildRequested) {
                signingConfig = signingConfigs.getByName("release")
            }
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
