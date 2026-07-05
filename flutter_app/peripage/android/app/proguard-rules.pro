# PENTING (fix Juli 2026): akar masalah "ModuleNotFoundError: No module
# named 'com'" yang berulang.
#
# `flutter build apk --release` SELALU menjalankan R8 code shrinking &
# obfuscation secara default -- ini bukan opt-in, tidak ada setting
# `isMinifyEnabled` yang perlu diaktifkan, R8 memang jalan otomatis tiap
# release build (lihat https://docs.flutter.dev/deployment/android).
#
# Python (lewat Chaquopy) memanggil NativeUsbTransport & NativeBleTransport
# HANYA lewat reflection berbasis STRING PERSIS:
#   from com.pyperipage import NativeUsbTransport
# R8 TIDAK TAHU soal pemanggilan ini -- itu di luar jangkauan analisis
# statis Kotlin/Java biasa. Class-nya tidak dihapus (karena MainActivity.kt
# memanggil .init() langsung), TAPI nama package & class-nya tetap
# di-obfuscate/rename oleh R8 (jadi sesuatu seperti "K.b"), sehingga string
# lookup Python di atas gagal total.
#
# -keep di bawah ini WAJIB ada supaya nama persis com.pyperipage.* dan semua
# member-nya (termasuk Kotlin `object` INSTANCE field) tidak berubah sama
# sekali, apa pun konfigurasi R8 ke depannya.
-keep class com.pyperipage.** { *; }
-keepnames class com.pyperipage.** { *; }
-keepclassmembers class com.pyperipage.** { *; }

# Chaquopy sendiri memakai reflection ekstensif untuk jembatan Python<->Java.
-keep class com.chaquo.python.** { *; }
-dontwarn com.chaquo.python.**
