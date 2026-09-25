import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.pm2550.chat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications and other plugins that use Java 8+ APIs.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.pm2550.chat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// 按 CPU 架构拆包（flutter build apk --split-per-abi）时，Flutter 默认给每个分包的
// versionCode 加偏移（armeabi-v7a +1000、arm64-v8a +2000），那是给 Play 商店区分分包用的。
// 我们自己分发：App 拿已安装的 versionCode 和服务器的 latestVersionCode 比较，
// 而且我们的版本号本身就是 1.1.52 -> 11052 这种编码，+1000/+2000 会和别的版本撞在一起
// （1.1.52 的 64 位包会变成 13052，比以后的 1.2.0=12000 还大，永远收不到更新）。
// 所以两个分包都用 pubspec 里的同一个 versionCode：它仍然比旧的整包大，覆盖安装没问题。
// 这段在 Flutter 插件之后注册，同一个 variant 上后执行，覆盖掉插件设的偏移。
android.applicationVariants.configureEach {
    val variant = this
    outputs.configureEach {
        (this as com.android.build.gradle.api.ApkVariantOutput).versionCodeOverride =
            variant.versionCode
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.15.0")
}
