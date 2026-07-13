package com.pyperipage

import android.graphics.BitmapFactory
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.NotFoundException
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer

/**
 * Deteksi barcode/QR pakai ZXing (com.google.zxing:core) -- pure Java/Kotlin,
 * TIDAK butuh native code (.so) sama sekali, jadi TIDAK kena masalah kelas
 * yang sama dengan pymupdf/pyusb/bleak (yang butuh native library tidak
 * tersedia di Chaquopy Android). Dipanggil dari Python (barcode_detect.py)
 * lewat Chaquopy Java interop -- pola yang sama dengan NativeUsbTransport/
 * NativeBleTransport.
 *
 * Dipakai untuk fitur "Auto-deselect halaman tanpa barcode" di Print
 * Screen -- deteksi halaman PDF/gambar mana yang TIDAK punya barcode/QR
 * (misal halaman ringkasan/invoice di tengah-tengah PDF label pengiriman
 * massal), supaya user tidak perlu manual uncheck satu-satu.
 */
object NativeBarcodeDetector {

    // MultiFormatReader otomatis coba SEMUA format yang didukung ZXing
    // (CODE_128, CODE_39, EAN_13, EAN_8, QR_CODE, PDF_417, DATA_MATRIX,
    // ITF, dll) -- mencakup hampir semua format yang dipakai label
    // pengiriman Shopee/TikTok/JNE/SPX/dll, tanpa perlu tahu format
    // spesifiknya di awal.
    private val reader = MultiFormatReader().apply {
        setHints(mapOf(DecodeHintType.TRY_HARDER to true))
    }

    /**
     * True kalau [pngBytes] (gambar halaman/label, format PNG) mengandung
     * minimal 1 barcode/QR terdeteksi.
     */
    @Synchronized
    fun hasBarcode(pngBytes: ByteArray): Boolean {
        return try {
            val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size) ?: return false
            val width = bitmap.width
            val height = bitmap.height
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

            val source = RGBLuminanceSource(width, height, pixels)
            val binaryBitmap = BinaryBitmap(HybridBinarizer(source))

            reader.reset()
            reader.decode(binaryBitmap)
            true
        } catch (e: NotFoundException) {
            // Ini kondisi NORMAL (tidak ada barcode ditemukan di gambar),
            // BUKAN error -- jangan di-treat sebagai kegagalan.
            false
        } catch (e: Exception) {
            // Kegagalan lain (gambar korup, format tidak didukung decoder
            // bitmap, dll) -- aman di-treat sebagai "tidak ada barcode"
            // (fail-safe: halaman tetap kelihatan, tidak auto-terhapus
            // gara-gara error teknis, cuma tidak ke-auto-select).
            false
        }
    }
}
