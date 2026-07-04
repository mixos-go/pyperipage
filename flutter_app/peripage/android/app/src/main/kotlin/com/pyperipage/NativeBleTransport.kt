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

    private lateinit var appContext: Context
    private lateinit var bluetoothAdapter: BluetoothAdapter

    private var gatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var negotiatedMtu: Int = DEFAULT_MTU
    private var writeLatch: CountDownLatch? = null
    private var writeSuccess: Boolean = false

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
     */
    fun discoverDevices(timeoutMs: Long): List<Map<String, Any?>> {
        val scanner = bluetoothAdapter.bluetoothLeScanner
            ?: return emptyList()
        val found = ConcurrentHashMap<String, Map<String, Any?>>()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device
                val name = try { device.name } catch (e: SecurityException) { null }
                if (name.isNullOrBlank()) return // device tanpa nama sulit dikenali user, skip
                found[device.address] = mapOf(
                    "name" to name,
                    "address" to device.address,
                    "rssi" to result.rssi
                )
            }
        }

        try {
            scanner.startScan(callback)
            Thread.sleep(timeoutMs)
        } catch (e: SecurityException) {
            return emptyList() // permission BLUETOOTH_SCAN belum di-grant
        } finally {
            try {
                scanner.stopScan(callback)
            } catch (e: Exception) {
                // Adapter mungkin sudah off, aman diabaikan.
            }
        }

        return found.values.toList()
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
                    g.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    connected = false
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
            }

            override fun onCharacteristicWrite(
                g: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                writeSuccess = status == BluetoothGatt.GATT_SUCCESS
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

        newGatt.requestMtu(247)

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
    fun write(data: ByteArray): Boolean {
        val g = gatt ?: return false
        val characteristic = writeCharacteristic ?: return false

        var offset = 0
        while (offset < data.size) {
            val end = (offset + negotiatedMtu).coerceAtMost(data.size)
            val chunk = data.copyOfRange(offset, end)

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
            if (!ok) return false

            // WRITE_TYPE_NO_RESPONSE tidak akan pernah memicu onCharacteristicWrite,
            // jadi jangan nunggu latch kalau memang pakai mode itu.
            if (writeType == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) {
                latch.await(5, TimeUnit.SECONDS)
                if (!writeSuccess) return false
            }

            Thread.sleep(2) // jeda kecil, sama seperti transport lama
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
        }
    }
}
