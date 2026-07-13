package com.pyperipage

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Transport BLE native, pengganti `bleak` yang TIDAK BISA jalan di Android
 * lewat Chaquopy -- backend Android bleak (`bleak.backends.p4android`)
 * hardcoded butuh `python-for-android` (import `jnius`, `android.broadcast`,
 * `android.permissions`), yang sama sekali tidak ada di Chaquopy.
 *
 * UNIVERSAL DEVICE SUPPORT: tidak hardcode ke 1 service/characteristic UUID
 * PeriPage saja. Setelah connect, semua service & characteristic di-scan,
 * lalu dipilih characteristic writable PERTAMA yang ditemukan (mengutamakan
 * UUID printer BLE yang umum dipakai lintas-merk seperti "ISSC Transparent
 * UART", lalu fallback ke characteristic writable apa pun). Ini persis pola
 * yang dipakai app printer thermal universal (RawBT, cat-printer, dll) yang
 * mendukung banyak merk printer BLE murah tanpa perlu tahu UUID persis
 * masing-masing.
 *
 * Dipanggil dari Python (peripage_a9/transport_ble.py) lewat Chaquopy:
 *   from com.pyperipage import NativeBleTransport
 *   NativeBleTransport.INSTANCE.discoverDevices(5000)
 *   NativeBleTransport.INSTANCE.connect(address, 10000)
 */
object NativeBleTransport {

    // UUID service printer BLE yang umum dipakai lintas-merk (bukan cuma
    // PeriPage) -- dipakai buat MEMPRIORITASKAN characteristic saat connect,
    // BUKAN buat memfilter/membatasi. Kalau tidak ada yang cocok, tetap
    // fallback ke characteristic writable apa pun yang ditemukan.
    private val KNOWN_PRINTER_SERVICE_PREFIXES = listOf(
        "49535343", // ISSC Transparent UART -- dipakai PeriPage, cat-printer, Goojprt, dll
        "0000ffe0", // HM-10 / banyak modul BLE UART generik Cina
        "6e400001", // Nordic UART Service (NUS) -- dipakai beberapa printer generik
    )

    private const val DEFAULT_MTU = 20 // fallback aman kalau requestMtu gagal/tidak didukung
    private const val MAX_WRITE_RETRIES = 5
    private const val WRITE_PACING_MS = 8L // dinaikkan dari 2ms -- kasih waktu printer proses buffer

    private lateinit var appContext: Context
    private lateinit var bluetoothAdapter: BluetoothAdapter

    private var gatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var negotiatedMtu: Int = DEFAULT_MTU
    private var writeLatch: CountDownLatch? = null
    private var mtuChangedLatch: CountDownLatch? = null
    private var writeSuccess: Boolean = false
    private var lastGattWriteStatus: Int = -1

    /** Terjemahkan kode status GATT ke pesan manusiawi -- kode-kode ini
     * datang dari BluetoothGatt Android SDK (banyak yang tidak
     * didokumentasikan resmi dengan jelas, tapi umum dikenal di ekosistem
     * BLE Android). Dipakai buat diagnostik yang actionable, bukan cuma
     * "status gagal" generik. */
    private fun gattStatusName(status: Int): String = when (status) {
        0 -> "GATT_SUCCESS"
        1 -> "GATT_INVALID_HANDLE"
        2 -> "GATT_READ_NOT_PERMITTED"
        3 -> "GATT_WRITE_NOT_PERMITTED"
        5 -> "GATT_INSUFFICIENT_AUTHENTICATION (perlu pairing/bonding?)"
        6 -> "GATT_REQUEST_NOT_SUPPORTED"
        7 -> "GATT_INVALID_OFFSET"
        13 -> "GATT_INVALID_ATTRIBUTE_LENGTH (data lebih besar dari MTU yang disepakati?)"
        15 -> "GATT_INSUFFICIENT_ENCRYPTION"
        133 -> "GATT_ERROR (0x85, error umum stack Android -- sering muncul kalau device sibuk/tidak responsif)"
        137 -> "GATT_CONNECTION_CONGESTED (koneksi padat, kirim terlalu cepat)"
        257 -> "GATT_FAILURE"
        else -> "kode tidak dikenal ($status)"
    }

    /** Detail kegagalan write TERAKHIR -- dipakai Python buat pesan error yang
     * jelas ("chunk mana, kenapa gagal") daripada cuma "koneksi terputus?". */
    var lastWriteError: String? = null
        private set

    /**
     * Status koneksi GATT SEBENARNYA (bukan cuma "objek Python masih ada").
     * Di-update tiap `onConnectionStateChange` callback fire -- termasuk
     * kalau Android/printer diam-diam DISCONNECT di background TANPA
     * user pernah pencet "Putuskan" (ini wajar terjadi di BLE, banyak
     * printer hemat-daya auto-disconnect setelah idle beberapa menit).
     * FIX Juli 2026: sebelumnya get_printer_status() cuma cek variabel
     * Python `_driver._transport is not None`, yang TETAP True walau
     * GATT connection aslinya sudah mati -- bikin UI nunjukin "Terhubung"
     * padahal print bakal langsung gagal di chunk pertama.
     */
    @Volatile
    private var isGattConnected = false

    fun isConnected(): Boolean = isGattConnected && gatt != null && writeCharacteristic != null

    fun init(context: Context) {
        appContext = context.applicationContext
        val manager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = manager.adapter
    }

    /**
     * Scan device BLE di sekitar selama [timeoutMs]. UNIVERSAL: mengembalikan
     * SEMUA device BLE yang punya nama (tidak difilter cuma nama "PeriPage"),
     * supaya user bisa connect ke printer merk/UUID apa pun, bukan cuma
     * PeriPage.
     *
     * PENTING (fix Juli 2026): return String JSON, BUKAN List<Map<String, Any?>>
     * langsung. Sebelumnya Python (transport_ble.py) melakukan
     * `[dict(d) for d in devices]` -- iterasi objek Kotlin Map lewat
     * reflection Chaquopy. R8 (SELALU aktif di build release Flutter,
     * lihat proguard-rules.pro) me-rename class internal Map/List Kotlin,
     * membuat Chaquopy gagal proxy objeknya dengan benar dan Python
     * melempar "'l' object is not iterable" (huruf 1 karakter itu literally
     * nama class HASIL OBFUSCATION). String JSON sama sekali tidak butuh
     * Chaquopy introspeksi objek Java/Kotlin apa pun -- cuma teks murni,
     * jadi kebal dari masalah rename class oleh R8.
     */
    fun discoverDevices(timeoutMs: Long): String {
        val scanner = bluetoothAdapter.bluetoothLeScanner
            ?: return "[]"
        val found = ConcurrentHashMap<String, JSONObject>()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device
                val name = try { device.name } catch (e: SecurityException) { null }
                if (name.isNullOrBlank()) return // device tanpa nama sulit dikenali user, skip
                val obj = JSONObject()
                obj.put("name", name)
                obj.put("address", device.address)
                obj.put("rssi", result.rssi)
                found[device.address] = obj
            }
        }

        try {
            scanner.startScan(callback)
            Thread.sleep(timeoutMs)
        } catch (e: SecurityException) {
            return "[]" // permission BLUETOOTH_SCAN belum di-grant
        } finally {
            try {
                scanner.stopScan(callback)
            } catch (e: Exception) {
                // Adapter mungkin sudah off, aman diabaikan.
            }
        }

        val array = JSONArray()
        for (obj in found.values) array.put(obj)
        return array.toString()
    }

    /**
     * Connect ke device BLE by address, discover services, lalu pilih
     * characteristic writable yang paling cocok (lihat KNOWN_PRINTER_SERVICE_PREFIXES).
     */
    fun connect(address: String, timeoutMs: Long): Boolean {
        val device: BluetoothDevice = try {
            bluetoothAdapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            return false
        }

        val connectLatch = CountDownLatch(1)
        var connected = false

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    connected = true
                    isGattConnected = true
                    g.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    connected = false
                    isGattConnected = false
                    connectLatch.countDown()
                }
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                connectLatch.countDown()
            }

            override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    // Margin aman 80% dari MTU (mengikuti perilaku transport lama).
                    negotiatedMtu = ((mtu - 3) * 0.8).toInt().coerceAtLeast(20)
                }
                // Countdown APA PUN hasilnya (sukses/gagal) -- yang penting
                // GATT queue sudah bebas dari operasi requestMtu yang
                // outstanding, supaya write() berikutnya aman dipanggil.
                mtuChangedLatch?.countDown()
            }

            override fun onCharacteristicWrite(
                g: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                writeSuccess = status == BluetoothGatt.GATT_SUCCESS
                lastGattWriteStatus = status
                writeLatch?.countDown()
            }
        }

        val newGatt = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(appContext, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(appContext, false, callback)
            }
        } catch (e: SecurityException) {
            return false
        }

        val gotConnection = connectLatch.await(timeoutMs, TimeUnit.MILLISECONDS)
        if (!gotConnection || !connected) {
            try { newGatt.close() } catch (e: Exception) { /* no-op */ }
            return false
        }

        // PENTING (fix Juli 2026): requestMtu() adalah operasi GATT ASYNC --
        // sebelumnya kode langsung lanjut ke findWritableCharacteristic() dan
        // return true TANPA nunggu callback onMtuChanged() selesai. Ini
        // melanggar aturan dasar Android BLE: operasi GATT tidak boleh
        // ditumpuk beruntun sebelum operasi sebelumnya selesai (queue-nya
        // cuma bisa proses 1 command GATT dalam satu waktu). Begitu write()
        // dipanggil oleh alur print tak lama setelah connect() return, GATT
        // stack masih "sibuk" menyelesaikan request MTU yang outstanding --
        // muncul sebagai GATT_ERROR (133) di write pertama, PERSIS gejala
        // yang dilaporkan: gagal di chunk offset 0 (chunk PERTAMA).
        val mtuLatch = CountDownLatch(1)
        mtuChangedLatch = mtuLatch
        newGatt.requestMtu(247)
        mtuLatch.await(3, TimeUnit.SECONDS) // kalau device tidak dukung MTU request, timeout wajar & tidak fatal

        // FIX (Juli 2026, lanjutan): walau sudah menunggu callback MTU
        // selesai (fix sebelumnya), write PERTAMA masih konsisten gagal di
        // offset 0 (terkonfirmasi via log: gagal baik untuk data 70 byte
        // maupun 8755 byte -- selalu di percobaan PERTAMA, apa pun ukuran
        // datanya). Ini gejala yang didokumentasikan luas di banyak
        // stack Bluetooth Android (khususnya chipset Samsung/Qualcomm
        // tertentu): GATT queue "kelihatan" bebas dari sisi API
        // (onMtuChanged sudah fire), tapi controller BLE fisik masih
        // butuh waktu tambahan untuk benar-benar stabil sebelum write
        // pertama reliable. Jeda kecil ini adalah workaround yang umum
        // dipakai komunitas Android BLE untuk kelas masalah ini.
        Thread.sleep(300)

        val characteristic = findWritableCharacteristic(newGatt)
        if (characteristic == null) {
            try { newGatt.close() } catch (e: Exception) { /* no-op */ }
            return false
        }

        gatt = newGatt
        writeCharacteristic = characteristic
        return true
    }

    /**
     * Cari characteristic writable di SEMUA service yang ditemukan.
     * Prioritas ke UUID printer yang dikenal (KNOWN_PRINTER_SERVICE_PREFIXES),
     * tapi kalau tidak ada yang cocok, tetap fallback ke characteristic
     * writable APA PUN -- inilah yang bikin support "device universal".
     */
    private fun findWritableCharacteristic(g: BluetoothGatt): BluetoothGattCharacteristic? {
        val writableProps = BluetoothGattCharacteristic.PROPERTY_WRITE or
            BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE

        var fallback: BluetoothGattCharacteristic? = null

        for (service in g.services) {
            val serviceUuidStr = service.uuid.toString().lowercase()
            for (characteristic in service.characteristics) {
                if (characteristic.properties and writableProps == 0) continue

                val isKnownPrefix = KNOWN_PRINTER_SERVICE_PREFIXES.any {
                    serviceUuidStr.startsWith(it.lowercase())
                }
                if (isKnownPrefix) {
                    return characteristic // prioritas tertinggi, langsung dipakai
                }
                if (fallback == null) {
                    fallback = characteristic // simpan sebagai cadangan universal
                }
            }
        }
        return fallback
    }

    /**
     * Kirim data, di-chunk sesuai MTU yang dinegosiasikan (mirroring
     * perilaku BleTransport lama yang pakai 80% margin dari MTU).
     */
    /**
     * Kirim data, di-chunk sesuai MTU yang dinegosiasikan. Print job PDF
     * multi-halaman bisa kirim RATUSAN chunk berurutan -- fix Juli 2026:
     * tambah retry per chunk (sebelumnya 1x gagal langsung abort semua
     * job, padahal kegagalan transient -- GATT busy, printer lagi proses
     * buffer, dll -- itu wajar terjadi sesekali di tengah transfer besar).
     */
    fun write(data: ByteArray): Boolean {
        val g = gatt ?: return false
        val characteristic = writeCharacteristic ?: return false

        var offset = 0
        while (offset < data.size) {
            val end = (offset + negotiatedMtu).coerceAtMost(data.size)
            val chunk = data.copyOfRange(offset, end)

            var chunkSucceeded = false
            var lastAttemptError = ""

            for (attempt in 1..MAX_WRITE_RETRIES) {
                val latch = CountDownLatch(1)
                writeLatch = latch
                writeSuccess = false

                val writeType = if (characteristic.properties and
                    BluetoothGattCharacteristic.PROPERTY_WRITE != 0
                ) {
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                } else {
                    BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                }

                val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    g.writeCharacteristic(characteristic, chunk, writeType) == BluetoothGatt.GATT_SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    characteristic.writeType = writeType
                    @Suppress("DEPRECATION")
                    characteristic.value = chunk
                    @Suppress("DEPRECATION")
                    g.writeCharacteristic(characteristic)
                }

                if (!ok) {
                    lastAttemptError = "GATT menolak writeCharacteristic (queue busy?)"
                } else if (writeType == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) {
                    val completed = latch.await(5, TimeUnit.SECONDS)
                    if (!completed) {
                        lastAttemptError = "Timeout menunggu onCharacteristicWrite (5 detik)"
                    } else if (!writeSuccess) {
                        lastAttemptError = "GATT status ${gattStatusName(lastGattWriteStatus)}"
                    } else {
                        chunkSucceeded = true
                    }
                } else {
                    // WRITE_TYPE_NO_RESPONSE: tidak ada callback, anggap sukses
                    // begitu writeCharacteristic() sendiri return true.
                    chunkSucceeded = true
                }

                if (chunkSucceeded) break

                // Backoff singkat sebelum retry -- kasih waktu printer/GATT
                // stack "napas" sebelum coba lagi.
                Thread.sleep(150L * attempt) // backoff dinaikkan dari 50ms -- total retry window ~2.25 detik (150+300+450+600+750)
            }

            if (!chunkSucceeded) {
                lastWriteError = "Gagal kirim chunk di offset $offset/${data.size} setelah " +
                    "$MAX_WRITE_RETRIES percobaan: $lastAttemptError"
                return false
            }

            Thread.sleep(WRITE_PACING_MS) // jeda kecil antar chunk, kasih waktu printer proses
            offset = end
        }
        return true
    }

    fun close() {
        try {
            gatt?.disconnect()
            gatt?.close()
        } catch (e: Exception) {
            // Best-effort cleanup.
        } finally {
            gatt = null
            writeCharacteristic = null
            negotiatedMtu = DEFAULT_MTU
            isGattConnected = false
        }
    }
}
