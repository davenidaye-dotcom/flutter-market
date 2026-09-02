plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.letou.letou_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.letou.letou_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 注意：Flutter 打 APK 时仍可能带上未在此列出的 ABI。
    // 测试包请用: --target-platform android-arm64,android-x64
    // 正式包请用: --target-platform android-arm,android-arm64
    // 或直接 scripts\build.bat test|pro apk
    flavorDimensions += "env"
    productFlavors {
        // 测试包：真机(arm64) + 雷电(x86_64)
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            ndk {
                abiFilters.clear()
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".test"
            ndk {
                abiFilters.clear()
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        // 正式包：仅真机
        create("pro") {
            dimension = "env"
            ndk {
                abiFilters.clear()
                abiFilters += listOf("armeabi-v7a", "arm64-v8a")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // R8 minify 会让每次打 release 慢很多；Flutter 体积主要靠 ABI，默认关闭。
            // 正式包若要再压一点：android/gradle.properties 加 letou.enableR8=true
            val enableR8 =
                (project.findProperty("letou.enableR8") as String?)?.equals("true", ignoreCase = true) == true
            isMinifyEnabled = enableR8
            isShrinkResources = enableR8
            if (enableR8) {
                proguardFiles(
                    getDefaultProguardFile("proguard-android-optimize.txt"),
                    "proguard-rules.pro",
                )
            }
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

dependencies {
    implementation("androidx.core:core-splashscreen:1.0.1")
}
