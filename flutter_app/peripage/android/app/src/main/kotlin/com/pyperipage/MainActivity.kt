package com.pyperipage

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import com.chaquo.python.PyObject
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.pyperipage/python"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Python if not already started
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeDriver" -> {
                    val transportType = call.argument<String>("transportType") ?: "usb"
                    handlePythonCall("python_service", "initialize_driver", result, transportType)
                }
                
                "connectPrinter" -> {
                    val deviceAddress = call.argument<String>("deviceAddress")
                    handlePythonCall("python_service", "connect_printer", result, deviceAddress)
                }
                
                "disconnectPrinter" -> {
                    handlePythonCall("python_service", "disconnect_printer", result)
                }
                
                "scanBleDevices" -> {
                    handlePythonCall("python_service", "scan_ble_devices", result)
                }
                
                "printImage" -> {
                    val imageData = call.argument<String>("imageData") ?: ""
                    val options = call.argument<Map<String, Any>>("options")
                    handlePythonCall("python_service", "print_image", result, imageData, options)
                }
                
                "printPdf" -> {
                    val pdfData = call.argument<String>("pdfData") ?: ""
                    val options = call.argument<Map<String, Any>>("options")
                    handlePythonCall("python_service", "print_pdf", result, pdfData, options)
                }
                
                "printText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val options = call.argument<Map<String, Any>>("options")
                    handlePythonCall("python_service", "print_text", result, text, options)
                }
                
                "getPrinterStatus" -> {
                    handlePythonCall("python_service", "get_printer_status", result)
                }
                
                "feedPaper" -> {
                    val lines = call.argument<Int>("lines") ?: 3
                    handlePythonCall("python_service", "feed_paper", result, lines)
                }
                
                "cutPaper" -> {
                    handlePythonCall("python_service", "cut_paper", result)
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Request necessary permissions
        requestPermissions()
    }
    
    private fun handlePythonCall(moduleName: String, functionName: String, result: MethodChannel.Result, vararg args: Any?) {
        try {
            val py = Python.getInstance()
            val module = py.getModule(moduleName)

            val pyArgs = args.filterNotNull().map { arg ->
                when (arg) {
                    is Map<*, *> -> {
                        val jsonStr = JSONObject(arg as Map<String, Any>).toString()
                        py.getModule("json").callAttr("loads", jsonStr)
                    }
                    else -> arg
                }
            }.toTypedArray()

            val pyResult = module.callAttr(functionName, *pyArgs)

            val kotlinResult = when {
                pyResult == null -> null
                pyResult.toString() == "True" -> true
                pyResult.toString() == "False" -> false
                pyResult.toString().matches(Regex("^-?\\d+$")) -> pyResult.toString().toInt()
                else -> {
                    try {
                        val jsonStr = pyResult.toString()
                        if (jsonStr.startsWith("{") || jsonStr.startsWith("[")) {
                            JSONObject(jsonStr).toString()
                        } else {
                            jsonStr
                        }
                    } catch (e: Exception) {
                        pyResult.toString()
                    }
                }
            }

            result.success(kotlinResult)
        } catch (e: Exception) {
            result.error("PYTHON_ERROR", e.message, e.stackTraceToString())
        }
    }
    
    private fun requestPermissions() {
        val permissions = mutableListOf<String>()
        
        // Bluetooth permissions for Android 12+
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
            // Location permission for older Android versions (needed for BLE)
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) 
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }
        
        if (permissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this,
                permissions.toTypedArray(),
                1001
            )
        }
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            // Handle permission result - all permissions granted or denied
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (!allGranted) {
                // Show message to user about required permissions
            }
        }
    }
}
