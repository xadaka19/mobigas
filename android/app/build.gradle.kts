plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mobigas.mobigas"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = System.getenv("MYAPP_UPLOAD_KEY_ALIAS") ?: "mobigaskey"
            keyPassword = System.getenv("MYAPP_UPLOAD_KEY_PASSWORD") ?: ""
            storeFile = file(System.getenv("MYAPP_UPLOAD_STORE_FILE") ?: "mobigas-release-key.jks")
            storePassword = System.getenv("MYAPP_UPLOAD_STORE_PASSWORD") ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.mobigas.mobigas"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
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
