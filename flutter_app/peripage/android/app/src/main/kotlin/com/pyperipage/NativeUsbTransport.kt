package com.pyperipage

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Transport USB native, pengganti `pyusb` (`usb.core.find()`) yang TIDAK BISA
 * jalan di Android:
 * 1. pyusb butuh backend libusb yang biasanya berujung "NoBackendError: No
 *    backend available" di Android tanpa root.
 * 2. Bahkan kalau libusb ada, app Android non-root tidak bisa enumerasi
 *    device USB mentah lewat filesystem seperti di Linux/Windows -- WAJIB
 *    lewat android.hardware.usb.UsbManager (minta izin user secara resmi).
 *
 * Dipanggil dari Python (peripage_a9/transport_usb.py) lewat Chaquopy:
 *   from com.pyperipage import NativeUsbTransport
 *   NativeUsbTransport.INSTANCE.connect(vid, pid)
 *
 * Interface method (connect/write/close) SENGAJA dibuat mirroring exact
 * kontrak lama `.connect()/.write(bytes)/.close()` supaya protocol.py dan
 * driver.py di Python TIDAK PERLU diubah sama sekali.
 */
object NativeUsbTransport {
    private const val ACTION_USB_PERMISSION = "com.pyperipage.USB_PERMISSION"
    private const val PERMISSION_TIMEOUT_SEC = 30L

    private lateinit var appContext: Context
    private lateinit var usbManager: UsbManager

    private var connection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var endpointOut: UsbEndpoint? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        usbManager = appContext.getSystemService(Context.USB_SERVICE) as UsbManager
    }

    /**
     * Cari & konek ke device USB printer.
     *
     * UNIVERSAL: kalau vendorId/productId diisi (mis. 0x09c5/0x0200 punya
     * PeriPage), device itu diprioritaskan. Kalau tidak ketemu, fallback ke
     * device USB manapun yang attached yang punya interface printer
     * (bInterfaceClass == USB_CLASS_PRINTER) ATAU minimal punya endpoint
     * bulk OUT yang bisa diklaim -- supaya printer thermal merk lain (bukan
     * cuma PeriPage) tetap bisa dipakai tanpa perlu tahu VID/PID-nya.
     */
    fun connect(vendorId: Int, productId: Int): Boolean {
        val candidates = usbManager.deviceList.values.toMutableList()
        if (candidates.isEmpty()) return false

        // Urutkan: device dengan VID/PID yang cocok duluan, baru sisanya.
        candidates.sortByDescending { it.vendorId == vendorId && it.productId == productId }

        for (device in candidates) {
            if (!requestPermissionSync(device)) continue
            if (tryClaimDevice(device)) {
                return true
            }
        }
        return false
    }

    private fun requestPermissionSync(device: UsbDevice): Boolean {
        if (usbManager.hasPermission(device)) return true

        val latch = CountDownLatch(1)
        var granted = false

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == ACTION_USB_PERMISSION) {
                    granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    latch.countDown()
                }
            }
        }

        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            appContext.registerReceiver(receiver, filter)
        }

        try {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
            val permissionIntent = PendingIntent.getBroadcast(
                appContext, 0, Intent(ACTION_USB_PERMISSION), flags
            )
            usbManager.requestPermission(device, permissionIntent)
            latch.await(PERMISSION_TIMEOUT_SEC, TimeUnit.SECONDS)
        } finally {
            try {
                appContext.unregisterReceiver(receiver)
            } catch (e: Exception) {
                // Sudah ke-unregister atau tidak pernah terdaftar, aman diabaikan.
            }
        }
        return granted
    }

    private fun tryClaimDevice(device: UsbDevice): Boolean {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            val outEp = findBulkOutEndpoint(intf) ?: continue

            val conn = usbManager.openDevice(device) ?: continue
            if (!conn.claimInterface(intf, true)) {
                conn.close()
                continue
            }

            connection = conn
            usbInterface = intf
            endpointOut = outEp
            return true
        }
        return false
    }

    private fun findBulkOutEndpoint(intf: UsbInterface): UsbEndpoint? {
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            if (ep.direction == UsbConstants.USB_DIR_OUT &&
                ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK
            ) {
                return ep
            }
        }
        return null
    }

    fun write(data: ByteArray): Boolean {
        val conn = connection ?: return false
        val ep = endpointOut ?: return false
        val sent = conn.bulkTransfer(ep, data, data.size, 5000)
        return sent >= 0
    }

    fun close() {
        try {
            connection?.let { conn ->
                usbInterface?.let { conn.releaseInterface(it) }
                conn.close()
            }
        } catch (e: Exception) {
            // Best-effort cleanup, sama seperti perilaku transport lama.
        } finally {
            connection = null
            usbInterface = null
            endpointOut = null
        }
    }
}
