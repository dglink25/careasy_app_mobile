plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") 
}

android {
    namespace = "com.careasy.careasy_app_mobile"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    signingConfigs {
        create("release") {
            keyAlias = System.getenv("KEY_ALIAS") ?: ""
            keyPassword = System.getenv("KEY_PASSWORD") ?: ""
            storeFile = System.getenv("KEYSTORE_PATH")?.let { file(it) }
            storePassword = System.getenv("STORE_PASSWORD") ?: ""
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.careasy.careasy_app_mobile"
        minSdk = 23 
        targetSdk = 34  // Remplacer flutter.targetSdkVersion par une valeur fixe
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")  // ← plus "debug"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.core:core-ktx:1.9.0")
    implementation("com.google.android.material:material:1.8.0")
    implementation("androidx.multidex:multidex:2.0.1")
    
    // Pusher - avec la bonne syntaxe Kotlin DSL
    implementation("com.pusher:pusher-java-client:2.4.4")
    
    // Pour les notifications locales
    implementation("androidx.localbroadcastmanager:localbroadcastmanager:1.1.0")
    
    // Pour l'enregistrement audio
    implementation("androidx.media:media:1.6.0")
}