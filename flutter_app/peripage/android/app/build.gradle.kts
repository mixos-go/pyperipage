plugins {
    id("com.android.application")
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.pyperipage"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pyperipage"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Chaquopy configuration
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // WAJIB ada -- tanpa ini, proguard-rules.pro tidak pernah dibaca R8
            // sama sekali walau file-nya ada, dan bug "No module named 'com'"
            // akan terus terjadi karena R8 tetap default-nya obfuscate semua.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

chaquopy {
    defaultConfig {
        version = "3.12"
        buildPython("/usr/bin/python3")
        pip {
            install("pillow")
            // pyusb & bleak DIHAPUS dari build Android (Juli 2026):
            // - pyusb butuh backend libusb yang di Android non-root berujung
            //   "NoBackendError: No backend available", dan app biasa juga
            //   tidak bisa enumerasi USB mentah tanpa lewat UsbManager resmi.
            // - bleak backend Android-nya (bleak.backends.p4android) hardcoded
            //   butuh python-for-android (import jnius, android.broadcast,
            //   android.permissions) -- SAMA SEKALI TIDAK ADA di Chaquopy.
            //   Tim BeeWare mengalami masalah identik (lihat
            //   github.com/beeware/beeware/issues/181).
            //   Transport USB & BLE untuk Android sekarang diimplementasikan
            //   NATIVE di Kotlin (NativeUsbTransport.kt / NativeBleTransport.kt)
            //   pakai UsbManager & BluetoothGatt langsung, dipanggil dari Python
            //   (transport_usb.py / transport_ble.py) lewat Chaquopy Java
            //   interop -- BUKAN lewat pip package lagi.
            //   Di desktop (Windows/Linux/macOS), pyusb & bleak tetap dipasang
            //   normal lewat pip biasa di core_python/requirements karena di
            //   sana keduanya jalan sempurna (PyInstaller build, tidak
            //   terpengaruh perubahan ini).
            //
            // pypdf2, reportlab, & pymupdf DIHAPUS dari build Android:
            // - pypdf2/reportlab tidak bisa rasterisasi PDF->gambar.
            // - pymupdf (fitz) TIDAK PUNYA wheel prebuilt untuk Android di
            //   index Chaquopy (chaquo.com/pypi-13.1), dan tidak bisa
            //   dikompilasi dari source di Android (butuh toolchain native
            //   C/C++ untuk build MuPDF, yang tidak tersedia di Chaquopy env
            //   -- CXX di-set ke 'Chaquopy_cannot_compile_native_code').
            //   Rasterisasi PDF->gambar untuk fitur print_pdf() di Android
            //   HARUS dipindah ke sisi Dart (pakai package `pdfx` atau
            //   `printing`), lalu kirim path/bytes gambar hasil render ke
            //   python_service.py -- bukan path PDF mentah.
            //   Di desktop (Windows/Linux/macOS), pymupdf tetap dipasang
            //   normal lewat pip biasa di core_python/requirements
            //   (PyInstaller build), jadi tidak terpengaruh perubahan ini.
        }
    }

    sourceSets {
        getByName("main") {
            srcDir("src/main/python")
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
