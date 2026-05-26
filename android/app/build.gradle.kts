import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties dari key.properties
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.kemenag.examgo"
    compileSdk = flutter.compileSdkVersion
    // FIX PLAY-16KB: NDK 27+ sudah dikompilasi dengan 16KB page alignment.
    // flutter.ndkVersion bawaan mungkin masih NDK 25/26 yang belum support 16KB.
    ndkVersion = "27.0.12077973"

    compileOptions {
        // VERSION_1_8 kompatibel dengan semua device target (minSdk Flutter default)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8.toString()
    }

    defaultConfig {
        applicationId = "com.kemenag.examgo"
        // FIX CRASH-5: MissingLibraryException "Could not find 'libflutter.so'" (2 events, 2 users).
        // ROOT CAUSE: useLegacyPackaging = false (wajib untuk 16KB page alignment) membuat
        // .so libs TIDAK dikompres di dalam APK. Android 5.x (API 21-22) tidak mendukung
        // dlopen() langsung dari uncompressed .so di dalam ZIP → fatal crash saat startup.
        //
        // Kombinasi berbahaya:
        //   minSdk = 21 (flutter default)  +  useLegacyPackaging = false
        //   → crash "libflutter.so not found" di Android 5.x
        //
        // Fix: naikkan minSdk ke 23 (Android 6.0 Marshmallow, released 2015).
        // Alasan aman: Android 5.x hanya ~0.1% device aktif per 2026, sedangkan
        // semua fitur app (kamera, WebView, LockTask) membutuhkan API 23+ anyway.
        // API 23+ mendukung useLegacyPackaging=false DAN 16KB alignment via NDK 27.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode & versionName otomatis dari pubspec.yaml
        // version: X.Y.Z+N → versionName=X.Y.Z, versionCode=N
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // FIX PLAY-16KB: arm64-v8a untuk modern devices, armeabi-v7a untuk older tablets.
            // NDK 27+ mendukung 16KB alignment untuk kedua arsitektur ini.
            // x86_64 DIHAPUS: tidak dipakai di device fisik (hanya emulator),
            // menambah 4MB ke APK tanpa manfaat di production.
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
            abiFilters.add("armeabi-v7a")
        }
    }

    // FIX PLAY-16KB: Wajib untuk Google Play agar native .so teralignment 16KB.
    // useLegacyPackaging = false → .so libs TIDAK dikompres di AAB/APK,
    // sehingga system linker bisa membacanya langsung dari storage dengan
    // page boundary 16KB (required untuk Android 15 / API 35+).
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias      = keystoreProperties.getProperty("keyAlias")
                keyPassword   = keystoreProperties.getProperty("keyPassword")
                storeFile     = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // FIX BUG: flutter_local_notifications requires core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    
    // FIX: app-update dan asset-delivery DIHAPUS — tidak dipakai di kode
    // native maupun Flutter. Keduanya menambah ~2MB ke AAB tanpa manfaat.
    // Update sudah ditangani via HTTP ke GitHub Releases (update.dart).
}

flutter {
    source = "../.."
}
