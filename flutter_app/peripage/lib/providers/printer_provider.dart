import 'dart:io';
import 'package:flutter/foundation.dart';
import '../data/models/printer_models.dart';
import '../core/services/api_service.dart';
import '../services/desktop_backend_service.dart';

/// Provider untuk mengelola state printer dan operasi print
class PrinterProvider with ChangeNotifier {
  final ApiService _apiService;
  
  PrinterProvider({ApiService? apiService}) 
      : _apiService = apiService ?? ApiService();

  // State variables
  PrinterStatus? _printerStatus;
  PrinterConfig? _printerConfig;
  bool _isLoading = false;
  String? _errorMessage;
  List<BleDevice> _bleDevices = [];
  File? _selectedFile;
  List<File> _selectedFiles = [];

  // Getters
  PrinterStatus? get printerStatus => _printerStatus;
  PrinterConfig? get printerConfig => _printerConfig;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<BleDevice> get bleDevices => _bleDevices;
  File? get selectedFile => _selectedFile;
  List<File> get selectedFiles => _selectedFiles;
  bool get isConnected => _printerStatus?.connected ?? false;
  bool get isServerAvailable => _serverAvailable;
  ApiService get apiService => _apiService;
  bool _serverAvailable = false;

  /// Check if server is available
  Future<bool> checkServerAvailability() async {
    try {
      await _apiService.healthCheck();
      _serverAvailable = true;
      notifyListeners();
      return true;
    } catch (e) {
      _serverAvailable = false;
      // Kalau di desktop, DesktopBackendService sudah nangkep exit code &
      // stderr ASLI dari proses backend (lihat startBackend()) -- itu jauh
      // lebih berguna daripada exception generik dari HTTP client
      // ("Connection refused" doang tidak bilang APA yang sebenarnya gagal).
      final backendError = DesktopBackendService().isDesktop
          ? DesktopBackendService().lastError
          : null;
      _errorMessage = backendError ?? e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Restart backend Python secara penuh (stop lalu start ulang), lalu cek
  /// lagi ketersediaannya. Dipakai tombol "Coba Lagi" di banner UI supaya
  /// user tidak perlu buka terminal/file manager sama sekali kalau backend
  /// gagal auto-start.
  Future<bool> retryBackend() async {
    if (!DesktopBackendService().isDesktop) return checkServerAvailability();

    _isLoading = true;
    notifyListeners();

    await DesktopBackendService().restartBackend();
    final ok = await checkServerAvailability();

    _isLoading = false;
    notifyListeners();
    return ok;
  }

  /// Load printer status
  Future<void> loadPrinterStatus() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _printerStatus = await _apiService.getPrinterStatus();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load printer config
  Future<void> loadPrinterConfig() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _printerConfig = await _apiService.getConfig();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Connect via USB
  Future<bool> connectUsb() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _apiService.connectUsb();
      await loadPrinterStatus();
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Connect via BLE
  Future<bool> connectBle({String? deviceAddress}) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _apiService.connectBle(deviceAddress: deviceAddress);
      await loadPrinterStatus();
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Discover BLE devices
  Future<void> discoverBleDevices() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _bleDevices = await _apiService.discoverBleDevices();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
      _bleDevices = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set paper width
  Future<bool> setPaperWidth(int widthMm) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _apiService.setPaperWidth(widthMm);
      await loadPrinterConfig();
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Select single file
  void selectFile(File file) {
    _selectedFile = file;
    notifyListeners();
  }

  /// Select multiple files
  void selectMultipleFiles(List<File> files) {
    _selectedFiles = files;
    notifyListeners();
  }

  /// Clear selected files
  void clearSelectedFiles() {
    _selectedFile = null;
    _selectedFiles = [];
    notifyListeners();
  }

  /// Print single image
  Future<bool> printImage(File imageFile, {int? paperWidthMm}) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _apiService.printImage(imageFile, paperWidthMm: paperWidthMm);
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Print PDF
  Future<bool> printPdf(File pdfFile, List<int> pages, {int? paperWidthMm}) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _apiService.printPdf(pdfFile, pages, paperWidthMm: paperWidthMm);
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Print batch
  Future<bool> printBatch(List<File> files, {int? paperWidthMm}) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _apiService.printBatch(files, paperWidthMm: paperWidthMm);
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Putus koneksi printer aktif (USB atau BLE).
  Future<bool> disconnect() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _apiService.disconnect();
      _printerStatus = null;
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
