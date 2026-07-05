package com.pyperipage

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import com.chaquo.python.PyObject
import org.json.JSONObject
import org.json.JSONArray
import java.util.concurrent.Executors

/**
 * MethodChannel handler untuk Chaquopy.
 *
 * PENTING: nama & signature method di sini HARUS sinkron dengan
 * python_service.py (fungsi Python) dan ApiService (lib/core/services/api_service.dart,
 * bagian mobile branch). Ketiganya adalah satu kontrak yang sama, cuma beda bahasa.
 *
 * Semua data biner (gambar, PDF) dikirim sebagai FILE PATH lokal, BUKAN base64 --
 * File di Android sudah punya path lokal yang bisa langsung dibaca Python lewat
 * Chaquopy tanpa perlu encode/decode base64 (lebih hemat memori untuk PDF besar).
 */
class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.pyperipage/printer"

    // Koneksi USB/BLE (scan, request permission, connect) bisa makan waktu
    // beberapa detik sampai puluhan detik (nunggu user approve dialog izin).
    // MethodChannel handler dipanggil di platform/main thread secara default --
    // kalau dijalankan langsung di situ, UI akan freeze / berpotensi ANR.
    // Semua panggilan ke Python sekarang dieksekusi di background thread ini,
    // hasilnya baru dikirim balik ke Dart lewat main thread (wajib untuk
    // MethodChannel.Result).
    //
    // PENTING (fix Juli 2026): thread baru dari Executors polos TIDAK otomatis
    // mewarisi Context ClassLoader milik app. Chaquopy meresolusi
    // `from com.pyperipage import ...` di Python lewat reflection Java yang
    // baca Context ClassLoader thread yang berjalan -- kalau thread itu
    // classloader-nya bootstrap/system (bukan classloader app), reflection
    // gagal nemu package sendiri sama sekali, muncul sebagai
    // "ModuleNotFoundError: No module named 'com'" di Python (gagal bahkan di
    // segmen PALING AWAL, sebelum coba resolusi com.pyperipage.NativeUsbTransport).
    // Makanya ThreadFactory di sini SENGAJA set contextClassLoader manual ke
    // classloader Activity ini, bukan mengandalkan inheritance default.
    private val backgroundExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "chaquopy-bg").apply {
            contextClassLoader = this@MainActivity.classLoader
        }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        // Native transport USB/BLE (pengganti pyusb/bleak yang tidak jalan di
        // Chaquopy Android) -- lihat NativeUsbTransport.kt & NativeBleTransport.kt.
        NativeUsbTransport.init(this)
        NativeBleTransport.init(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectUsb" -> {
                    handlePythonCall("connect_usb", result)
                }

                "connectBle" -> {
                    val deviceAddress = call.argument<String>("deviceAddress")
                    val deviceName = call.argument<String>("deviceName")
                    handlePythonCall("connect_ble", result, deviceAddress, deviceName)
                }

                "disconnect" -> {
                    handlePythonCall("disconnect_printer", result)
                }

                "discoverBleDevices" -> {
                    val timeout = call.argument<Double>("timeout") ?: 5.0
                    handlePythonCall("discover_ble_devices", result, timeout)
                }

                "getPrinterStatus" -> {
                    handlePythonCall("get_printer_status", result)
                }

                "getConfig" -> {
                    handlePythonCall("get_config", result)
                }

                "setPaperWidth" -> {
                    val widthMm = call.argument<Int>("widthMm")
                    handlePythonCall("set_paper_width", result, widthMm)
                }

                "previewImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val paperWidthMm = call.argument<Int>("paperWidthMm")
                    val smartCrop = call.argument<Boolean>("smartCrop") ?: true
                    handlePythonCall("preview_image", result, imagePath, paperWidthMm, smartCrop)
                }

                "printImage" -> {
                    val imagePath = call.argument<String>("imagePath")
                    val paperWidthMm = call.argument<Int>("paperWidthMm")
                    val smartCrop = call.argument<Boolean>("smartCrop") ?: true
                    handlePythonCall("print_image", result, imagePath, paperWidthMm, smartCrop)
                }

                "printPdfPages" -> {
                    // Ganti dari "printPdf" (Juli 2026): PDF sekarang dirender jadi
                    // gambar di sisi Dart (pdfx) dulu, karena Chaquopy tidak bisa
                    // pasang fitz/pymupdf. imagePaths[i] adalah hasil render pages[i].
                    val imagePaths = call.argument<List<String>>("imagePaths") ?: listOf()
                    val pages = call.argument<List<Int>>("pages") ?: listOf()
                    val paperWidthMm = call.argument<Int>("paperWidthMm")
                    val smartCrop = call.argument<Boolean>("smartCrop") ?: true
                    handlePythonCall("print_pdf_pages", result, imagePaths, pages, paperWidthMm, smartCrop)
                }

                "printBatch" -> {
                    val filePaths = call.argument<List<String>>("filePaths") ?: listOf()
                    val paperWidthMm = call.argument<Int>("paperWidthMm")
                    val smartCrop = call.argument<Boolean>("smartCrop") ?: true
                    handlePythonCall("print_batch", result, filePaths, paperWidthMm, smartCrop)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        requestPermissions()
    }

    /**
     * Konversi argumen Kotlin -> PyObject lalu panggil fungsi Python di module
     * python_service, konversi balik hasilnya (dict Python) jadi JSON string
     * yang di-decode ulang di sisi Dart.
     *
     * Dieksekusi di background thread (lihat backgroundExecutor) karena
     * connect_usb/connect_ble/discover_ble_devices bisa blocking lama
     * (nunggu dialog izin USB, scan BLE, dsb). result.success()/error() HARUS
     * tetap dipanggil di main thread, makanya di-post lewat mainHandler.
     */
    private fun handlePythonCall(functionName: String, result: MethodChannel.Result, vararg args: Any?) {
        backgroundExecutor.execute {
            try {
                val py = Python.getInstance()
                val module = py.getModule("python_service")

                val pyArgs = args.map { arg ->
                    when (arg) {
                        null -> null
                        is List<*> -> {
                            val jsonArr = JSONArray(arg)
                            py.getModule("json").callAttr("loads", jsonArr.toString())
                        }
                        else -> arg
                    }
                }.toTypedArray()

                val pyResult: PyObject = module.callAttr(functionName, *pyArgs)

                // python_service.py selalu return dict -- serialize balik via json.dumps
                // di sisi Python biar strukturnya (nested dict/list) terjaga persis,
                // baru di-decode lagi di Dart pakai json.decode().
                val jsonModule = py.getModule("json")
                val jsonStr = jsonModule.callAttr("dumps", pyResult).toString()

                mainHandler.post { result.success(jsonStr) }
            } catch (e: Exception) {
                mainHandler.post { result.error("PYTHON_ERROR", e.message, e.stackTraceToString()) }
            }
        }
    }

    private fun requestPermissions() {
        val permissions = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.BLUETOOTH_SCAN)
            }
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }

        if (permissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, permissions.toTypedArray(), 1001)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (!allGranted) {
                // TODO: tampilkan pesan ke user kalau permission ditolak
            }
        }
    }
}
