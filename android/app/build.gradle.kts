plugins {
    id("com.android.application")
    id("kotlin-android")
    id("kotlin-kapt")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace  = "com.example.crm_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.crm_app"
        minSdk        = 29   // Android 10+ required for foregroundServiceType="microphone"
        targetSdk     = 36
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // HTTP client for uploading recordings to backend (single entry — removed duplicate)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // Room (local DB)
    implementation("androidx.room:room-runtime:2.7.0")
    kapt("androidx.room:room-compiler:2.7.0")
}