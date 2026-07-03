import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/printer_provider.dart';
import '../../data/models/printer_models.dart';

/// Print Screen - Fitur utama untuk print PDF, Gambar, dan Label
class PrintScreen extends StatefulWidget {
  const PrintScreen({super.key});

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  File? _selectedFile;
  List<File> _selectedFiles = [];
  bool _isBatchMode = false;
  int? _selectedPaperWidth;
  List<int> _pdfPages = []; // Untuk select halaman PDF
  bool _showPreview = false;
  String? _previewImageBase64;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final provider = context.read<PrinterProvider>();
    await provider.loadPrinterConfig();
    if (provider.printerConfig != null) {
      setState(() {
        _selectedPaperWidth = provider.printerConfig!.currentPaperWidth;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'bmp'],
        allowMultiple: _isBatchMode,
      );

      if (result != null && result.files.single.path != null) {
        if (_isBatchMode) {
          setState(() {
            _selectedFiles = result.paths
                .where((path) => path != null)
                .map((path) => File(path!))
                .toList();
            _selectedFile = null;
          });
        } else {
          setState(() {
            _selectedFile = File(result.files.single.path!);
            _selectedFiles = [];
          });
          // Auto preview untuk single file
          await _generatePreview();
        }
      }
    } catch (e) {
      _showError('Gagal memilih file: $e');
    }
  }

  Future<void> _generatePreview() async {
    if (_selectedFile == null) return;

    final provider = context.read<PrinterProvider>();
    
    // Cek apakah file PDF atau image
    final extension = _selectedFile!.path.split('.').last.toLowerCase();
    
    if (extension == 'pdf') {
      // Untuk PDF, tampilkan dialog pilih halaman
      _showPdfPageSelector();
    } else {
      // Untuk image, generate preview
      try {
        setState(() => _showPreview = true);
        // Preview akan di-generate oleh backend
        final preview = await provider.apiService.previewImage(
          _selectedFile!,
          paperWidthMm: _selectedPaperWidth,
        );
        setState(() {
          _previewImageBase64 = preview;
        });
      } catch (e) {
        _showError('Gagal generate preview: $e');
      } finally {
        setState(() => _showPreview = false);
      }
    }
  }

  void _showPdfPageSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pilih Halaman PDF'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Masukkan nomor halaman (contoh: 1,2,3 atau 1-5)'),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Halaman',
                hintText: '1,2,3 atau 1-5',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                // Parse input menjadi list halaman
                // Implementasi sederhana: split by comma atau range
                try {
                  if (value.contains('-')) {
                    final parts = value.split('-');
                    final start = int.parse(parts[0].trim());
                    final end = int.parse(parts[1].trim());
                    _pdfPages = List.generate(end - start + 1, (i) => start + i);
                  } else {
                    _pdfPages = value
                        .split(',')
                        .map((s) => int.parse(s.trim()))
                        .toList();
                  }
                } catch (e) {
                  _pdfPages = [1]; // Default halaman 1
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_pdfPages.isEmpty) {
                _pdfPages = [1];
              }
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _print() async {
    if (_selectedFile == null && _selectedFiles.isEmpty) {
      _showError('Pilih file terlebih dahulu');
      return;
    }

    final provider = context.read<PrinterProvider>();
    
    try {
      bool success = false;
      
      if (_isBatchMode && _selectedFiles.isNotEmpty) {
        // Print batch
        success = await provider.printBatch(
          _selectedFiles,
          paperWidthMm: _selectedPaperWidth,
        );
      } else if (_selectedFile != null) {
        final extension = _selectedFile!.path.split('.').last.toLowerCase();
        
        if (extension == 'pdf') {
          // Print PDF
          if (_pdfPages.isEmpty) _pdfPages = [1];
          success = await provider.printPdf(
            _selectedFile!,
            _pdfPages,
            paperWidthMm: _selectedPaperWidth,
          );
        } else {
          // Print image
          success = await provider.printImage(
            _selectedFile!,
            paperWidthMm: _selectedPaperWidth,
          );
        }
      }

      if (success) {
        _showSuccess('Print berhasil!');
        _clearSelection();
      } else {
        _showError('Print gagal');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedFile = null;
      _selectedFiles = [];
      _previewImageBase64 = null;
      _pdfPages = [];
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Print'),
        actions: [
          IconButton(
            icon: Icon(_isBatchMode ? Icons.looks_one : Icons.looks_3),
            tooltip: _isBatchMode ? 'Mode Single' : 'Mode Batch',
            onPressed: () {
              setState(() {
                _isBatchMode = !_isBatchMode;
                _clearSelection();
              });
            },
          ),
        ],
      ),
      body: Consumer<PrinterProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection Status
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          provider.isConnected
                              ? Icons.print
                              : Icons.print_disabled,
                          color: provider.isConnected
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provider.isConnected
                                    ? 'Printer Terhubung'
                                    : 'Printer Tidak Terhubung',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                provider.printerStatus?.transportType ??
                                    'Belum terhubung',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Paper Width Selection
                if (provider.printerConfig != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ukuran Kertas',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: _selectedPaperWidth,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Lebar Kertas (mm)',
                            ),
                            items: provider.printerConfig!
                                .supportedPaperWidths
                                .map((width) => DropdownMenuItem(
                                      value: width,
                                      child: Text('$width mm'),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedPaperWidth = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // File Selection
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isBatchMode ? 'Pilih Multiple Files' : 'Pilih File',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.folder_open),
                          label: Text(_isBatchMode
                              ? 'Pilih Multiple Files'
                              : 'Pilih File'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_selectedFile != null) ...[
                          ListTile(
                            leading: const Icon(Icons.insert_drive_file),
                            title: Text(_selectedFile!.path.split('/').last),
                            subtitle: Text(
                              '${(_selectedFile!.lengthSync() / 1024).toStringAsFixed(1)} KB',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _clearSelection,
                            ),
                          ),
                        ] else if (_selectedFiles.isNotEmpty) ...[
                          ListTile(
                            leading: const Icon(Icons.folder),
                            title: Text('${_selectedFiles.length} files'),
                            subtitle: Text(
                              _selectedFiles
                                  .map((f) => f.path.split('/').last)
                                  .join(', '),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: _clearSelection,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Preview Section (untuk image)
                if (_showPreview && _previewImageBase64 != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Preview',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Image.memory(
                              base64Decode(_previewImageBase64!),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Text('Preview tidak tersedia');
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Print Button
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: provider.isLoading ? null : _print,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: provider.isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.print),
                            SizedBox(width: 8),
                            Text(
                              'PRINT',
                              style: TextStyle(fontSize: 18),
                            ),
                          ],
                        ),
                ),

                // Info text
                const SizedBox(height: 16),
                Text(
                  'Support: PDF (Shopee/TikTok labels), PNG, JPG, BMP',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
