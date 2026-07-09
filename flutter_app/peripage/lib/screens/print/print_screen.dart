import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:lottie/lottie.dart';
import '../../providers/printer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../data/models/printer_models.dart';
import '../crop/manual_crop_screen.dart';

/// Print Screen - Fitur utama untuk print PDF, Gambar, dan Label.
///
/// REBUILD (Juli 2026):
/// - Fix bug preview: sebelumnya `_showPreview` di-set balik ke false di
///   blok `finally` SEBELUM widget render, jadi hasil preview TIDAK PERNAH
///   kelihatan sama sekali walau API call-nya sukses.
/// - Tambah toggle Smart Crop / Manual Crop (dulu selalu smart crop, tidak
///   bisa dimatikan sama sekali).
/// - PDF sekarang render THUMBNAIL per halaman (grid, bisa select/deselect
///   multi-halaman) -- dulu cuma dialog ketik manual "1,2,3 atau 1-5".
class PrintScreen extends StatefulWidget {
  final bool initialBatchMode;

  const PrintScreen({super.key, this.initialBatchMode = false});

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  File? _selectedFile;
  List<File> _selectedFiles = [];
  late bool _isBatchMode;
  int? _selectedPaperWidth;
  bool _smartCrop = true;
  Map<int, CropRect> _manualCrops = {}; // index -> crop rect (0-1 normalized)

  // PDF page selection
  List<Uint8ListThumb> _pdfThumbnails = [];
  Set<int> _selectedPages = {}; // 0-indexed
  bool _loadingThumbnails = false;

  // Preview gambar (non-PDF)
  bool _isLoadingPreview = false;
  String? _previewImageBase64;

  @override
  void initState() {
    super.initState();
    _isBatchMode = widget.initialBatchMode;
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final provider = context.read<PrinterProvider>();
    await provider.loadPrinterConfig();
    if (provider.printerConfig != null && mounted) {
      setState(() {
        _selectedPaperWidth = provider.printerConfig!.currentPaperWidth;
      });
    }
  }

  bool get _isPdf => _selectedFile != null && _selectedFile!.path.toLowerCase().endsWith('.pdf');

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'bmp'],
        allowMultiple: _isBatchMode,
      );

      if (result == null) return;

      if (_isBatchMode) {
        setState(() {
          _selectedFiles = result.paths.where((p) => p != null).map((p) => File(p!)).toList();
          _selectedFile = null;
          _pdfThumbnails = [];
          _selectedPages = {};
          _previewImageBase64 = null;
        });
        return;
      }

      if (result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      setState(() {
        _selectedFile = file;
        _selectedFiles = [];
        _previewImageBase64 = null;
        _pdfThumbnails = [];
        _selectedPages = {};
      });

      if (file.path.toLowerCase().endsWith('.pdf')) {
        await _loadPdfThumbnails(file);
      } else {
        await _generateImagePreview();
      }
    } catch (e) {
      _showError('Gagal memilih file: $e');
    }
  }

  /// Render THUMBNAIL tiap halaman PDF (bukan cuma minta user ketik nomor
  /// halaman manual) supaya user bisa lihat & pilih halaman secara visual.
  Future<void> _loadPdfThumbnails(File pdfFile) async {
    setState(() => _loadingThumbnails = true);
    try {
      final document = await PdfDocument.openFile(pdfFile.path);
      final thumbs = <Uint8ListThumb>[];
      try {
        for (int i = 1; i <= document.pagesCount; i++) {
          final page = await document.getPage(i);
          try {
            final rendered = await page.render(
              width: page.width * 0.6,
              height: page.height * 0.6,
              format: PdfPageImageFormat.png,
            );
            if (rendered != null) {
              thumbs.add(Uint8ListThumb(pageIndex: i - 1, bytes: rendered.bytes));
            }
          } finally {
            await page.close();
          }
        }
      } finally {
        await document.close();
      }
      if (!mounted) return;
      setState(() {
        _pdfThumbnails = thumbs;
        _selectedPages = {0}; // default: halaman pertama terpilih
      });
    } catch (e) {
      _showError('Gagal render preview PDF: $e');
    } finally {
      if (mounted) setState(() => _loadingThumbnails = false);
    }
  }

  Future<void> _generateImagePreview() async {
    if (_selectedFile == null) return;
    final provider = context.read<PrinterProvider>();
    setState(() => _isLoadingPreview = true);
    try {
      final preview = await provider.apiService.previewImage(
        _selectedFile!,
        paperWidthMm: _selectedPaperWidth,
        smartCrop: _smartCrop,
        cropRect: _smartCrop ? null : _manualCrops[0],
      );
      if (!mounted) return;
      setState(() => _previewImageBase64 = preview);
    } catch (e) {
      _showError('Gagal generate preview: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPreview = false);
    }
  }

  /// Dipanggil ulang setiap toggle Smart/Manual Crop diubah -- preview harus
  /// ikut refresh supaya WYSIWYG (What You See Is What You Print) tetap benar.
  Future<void> _onSmartCropChanged(bool value) async {
    setState(() => _smartCrop = value);
    if (_selectedFile != null && !_isPdf) {
      await _generateImagePreview();
    }
  }

  void _togglePageSelection(int pageIndex) {
    setState(() {
      if (_selectedPages.contains(pageIndex)) {
        _selectedPages.remove(pageIndex);
      } else {
        _selectedPages.add(pageIndex);
      }
    });
  }

  Future<void> _print() async {
    if (_selectedFile == null && _selectedFiles.isEmpty) {
      _showError('Pilih file terlebih dahulu');
      return;
    }
    if (_isPdf && _selectedPages.isEmpty) {
      _showError('Pilih minimal 1 halaman untuk dicetak');
      return;
    }

    final provider = context.read<PrinterProvider>();

    try {
      bool success = false;

      if (_isBatchMode && _selectedFiles.isNotEmpty) {
        success = await provider.printBatch(
          _selectedFiles,
          paperWidthMm: _selectedPaperWidth,
          smartCrop: _smartCrop,
          cropRects: _smartCrop ? null : _manualCrops,
        );
        if (success) {
          for (final f in _selectedFiles) {
            await provider.recordRecentFile(path: f.path, name: f.path.split(Platform.pathSeparator).last, type: 'batch');
          }
        }
      } else if (_selectedFile != null) {
        if (_isPdf) {
          final pages = _selectedPages.toList()..sort();
          success = await provider.printPdf(
            _selectedFile!,
            pages,
            paperWidthMm: _selectedPaperWidth,
            smartCrop: _smartCrop,
            cropRects: _smartCrop ? null : _manualCrops,
          );
          if (success) {
            await provider.recordRecentFile(path: _selectedFile!.path, name: _selectedFile!.path.split(Platform.pathSeparator).last, type: 'pdf');
          }
        } else {
          success = await provider.printImage(
            _selectedFile!,
            paperWidthMm: _selectedPaperWidth,
            smartCrop: _smartCrop,
            cropRect: _smartCrop ? null : _manualCrops[0],
          );
          if (success) {
            await provider.recordRecentFile(path: _selectedFile!.path, name: _selectedFile!.path.split(Platform.pathSeparator).last, type: 'image');
          }
        }
      }

      if (success) {
        _showSuccessAnimation();
        _showSuccess('Print berhasil!');
        _clearSelection();
      } else {
        _showError(provider.errorMessage ?? 'Print gagal');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  /// Dipanggil dalam mode "Manual Crop" -- buka ManualCropScreen dengan
  /// gambar yang sesuai (single file / thumbnail tiap halaman PDF yang
  /// terpilih / tiap file batch), lalu simpan hasil crop rect per halaman.
  Future<void> _openManualCropEditor() async {
    List<Uint8List> images = [];
    List<String> labels = [];
    Map<int, CropRect> initial = {};

    if (_isBatchMode && _selectedFiles.isNotEmpty) {
      for (int i = 0; i < _selectedFiles.length; i++) {
        try {
          images.add(await _selectedFiles[i].readAsBytes());
          labels.add(_selectedFiles[i].path.split(Platform.pathSeparator).last);
        } catch (_) {
          // File PDF di batch tidak didukung editor crop (butuh render dulu) -- skip.
        }
      }
      initial = _manualCrops;
    } else if (_isPdf && _pdfThumbnails.isNotEmpty) {
      final selected = _selectedPages.toList()..sort();
      if (selected.isEmpty) {
        _showError('Pilih minimal 1 halaman dulu sebelum edit crop.');
        return;
      }
      for (final pageIdx in selected) {
        final thumb = _pdfThumbnails.firstWhere((t) => t.pageIndex == pageIdx);
        images.add(thumb.bytes);
        labels.add('Halaman ${pageIdx + 1}');
      }
      // Map index lokal (posisi di `images`) -> pageIdx asli, supaya hasil
      // crop tersimpan dengan key page index yang benar.
      final localToPage = {for (int i = 0; i < selected.length; i++) i: selected[i]};
      for (final entry in localToPage.entries) {
        if (_manualCrops.containsKey(entry.value)) initial[entry.key] = _manualCrops[entry.value]!;
      }
      final result = await Navigator.push<Map<int, CropRect>>(
        context,
        MaterialPageRoute(builder: (_) => ManualCropScreen(images: images, labels: labels, initialCrops: initial)),
      );
      if (result != null) {
        setState(() {
          for (final entry in result.entries) {
            _manualCrops[localToPage[entry.key]!] = entry.value;
          }
        });
        _showSuccess('Crop manual disimpan untuk ${result.length} halaman.');
      }
      return;
    } else if (_selectedFile != null) {
      images.add(await _selectedFile!.readAsBytes());
      labels.add(_selectedFile!.path.split(Platform.pathSeparator).last);
      initial = _manualCrops;
    } else {
      _showError('Pilih file terlebih dahulu.');
      return;
    }

    if (images.isEmpty) return;
    if (!mounted) return;

    final result = await Navigator.push<Map<int, CropRect>>(
      context,
      MaterialPageRoute(builder: (_) => ManualCropScreen(images: images, labels: labels, initialCrops: initial)),
    );
    if (result != null) {
      setState(() => _manualCrops = result);
      _showSuccess('Crop manual disimpan.');
      if (!_isPdf && !_isBatchMode) await _generateImagePreview();
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedFile = null;
      _selectedFiles = [];
      _previewImageBase64 = null;
      _pdfThumbnails = [];
      _selectedPages = {};
      _manualCrops = {};
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppTheme.errorColor));
  }

  /// Overlay animasi centang hijau singkat (auto-dismiss) setelah print
  /// sukses -- feedback visual yang lebih hidup daripada SnackBar polos.
  void _showSuccessAnimation() {
    if (!mounted) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'success',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (dialogContext, anim1, anim2) {
        Future.delayed(const Duration(milliseconds: 1100), () {
          // dialogContext dipakai di dalam callback async (Future.delayed) --
          // `.mounted` di sini AMAN dipanggil walau context sudah disposed
          // (beda dengan ModalRoute.of() yang bisa throw di context mati),
          // jadi ini setara "mounted check" resmi buat BuildContext dialog
          // yang tidak attached ke sebuah State.
          if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
        });
        return Center(
          child: SizedBox(
            width: 140,
            height: 140,
            child: Lottie.asset(
              'assets/lottie/success_check.json',
              repeat: false,
              errorBuilder: (c, e, s) => const Icon(Icons.check_circle, color: AppTheme.successColor, size: 100),
            ),
          ),
        );
      },
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppTheme.successColor));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Print'),
        actions: [
          IconButton(
            icon: Icon(_isBatchMode ? Icons.looks_one : Icons.copy_all),
            tooltip: _isBatchMode ? 'Mode single file' : 'Mode batch (multi file)',
            onPressed: () => setState(() {
              _isBatchMode = !_isBatchMode;
              _clearSelection();
            }),
          ),
        ],
      ),
      body: Consumer<PrinterProvider>(
        builder: (context, provider, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(UiConstants.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionCard(context, provider),
                const SizedBox(height: UiConstants.spacingMd),
                if (provider.printerConfig != null) _buildPaperWidthCard(context, provider),
                const SizedBox(height: UiConstants.spacingMd),
                _buildCropModeCard(context),
                const SizedBox(height: UiConstants.spacingMd),
                _buildFilePickerCard(context),
                const SizedBox(height: UiConstants.spacingMd),
                if (_isPdf) _buildPdfPageGrid(context),
                if (!_isPdf && _selectedFile != null) _buildImagePreview(context),
                const SizedBox(height: UiConstants.spacingLg),
                ElevatedButton(
                  onPressed: provider.isLoading ? null : _print,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                  child: provider.isLoading
                      ? SizedBox(
                          height: 40,
                          width: 60,
                          child: Lottie.asset(
                            'assets/lottie/printer_printing.json',
                            errorBuilder: (c, e, s) => const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.print),
                            const SizedBox(width: 8),
                            Text(_isPdf && _selectedPages.length > 1 ? 'PRINT ${_selectedPages.length} HALAMAN' : 'PRINT', style: const TextStyle(fontSize: 18)),
                          ],
                        ),
                ),
                const SizedBox(height: UiConstants.spacingMd),
                Text(
                  'Support: PDF (Shopee/TikTok labels), PNG, JPG, BMP',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context, PrinterProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingMd),
        child: Row(
          children: [
            Icon(provider.isConnected ? Icons.print : Icons.print_disabled, color: provider.isConnected ? AppTheme.successColor : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(provider.isConnected ? 'Printer Terhubung' : 'Printer Tidak Terhubung', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(provider.printerStatus?.transportType ?? 'Belum terhubung', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaperWidthCard(BuildContext context, PrinterProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ukuran Kertas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedPaperWidth,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Lebar Kertas (mm)'),
              items: provider.printerConfig!.supportedPaperWidths.map((w) => DropdownMenuItem(value: w, child: Text('$w mm'))).toList(),
              onChanged: (value) async {
                setState(() => _selectedPaperWidth = value);
                if (_selectedFile != null && !_isPdf) await _generateImagePreview();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Toggle Smart Crop (auto-trim whitespace) vs Manual Crop (resize apa
  /// adanya, tanpa trim) -- diminta agar user bisa pilih, tidak dipaksa
  /// smart crop selalu.
  Widget _buildCropModeCard(BuildContext context) {
    final hasFile = _selectedFile != null || _selectedFiles.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_smartCrop ? Icons.auto_fix_high : Icons.crop, color: AppTheme.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_smartCrop ? 'Smart Crop' : 'Manual Crop', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        _smartCrop ? 'Otomatis potong margin/whitespace kosong' : 'Resize apa adanya, tanpa potong margin',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(value: _smartCrop, onChanged: _onSmartCropChanged, activeThumbColor: AppTheme.primaryColor),
              ],
            ),
            if (!_smartCrop) ...[
              const SizedBox(height: UiConstants.spacingSm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: hasFile ? _openManualCropEditor : null,
                  icon: const Icon(Icons.crop_free),
                  label: Text(_manualCrops.isEmpty ? 'Edit Crop Manual' : 'Edit Crop Manual (${_manualCrops.length} diatur)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isBatchMode ? 'Pilih Multiple Files' : 'Pilih File', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: Text(_isBatchMode ? 'Pilih Multiple Files' : 'Pilih File'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 12),
            if (_selectedFile != null)
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: Text(_selectedFile!.path.split(Platform.pathSeparator).last),
                subtitle: Text('${(_selectedFile!.lengthSync() / 1024).toStringAsFixed(1)} KB'),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
              )
            else if (_selectedFiles.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.folder),
                title: Text('${_selectedFiles.length} files'),
                subtitle: Text(_selectedFiles.map((f) => f.path.split(Platform.pathSeparator).last).join(', ')),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
              ),
          ],
        ),
      ),
    );
  }

  /// Grid thumbnail PDF -- select/deselect per halaman, GANTI dari dialog
  /// ketik manual "1,2,3 atau 1-5" yang sebelumnya jadi satu-satunya cara
  /// pilih halaman (dan tidak ada preview visualnya sama sekali).
  Widget _buildPdfPageGrid(BuildContext context) {
    if (_loadingThumbnails) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: UiConstants.spacingLg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_pdfThumbnails.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pilih Halaman (${_selectedPages.length}/${_pdfThumbnails.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _selectedPages = _pdfThumbnails.map((t) => t.pageIndex).toSet()),
                      child: const Text('Semua'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selectedPages = {}),
                      child: const Text('Bersihkan'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.72),
              itemCount: _pdfThumbnails.length,
              itemBuilder: (context, i) {
                final thumb = _pdfThumbnails[i];
                final selected = _selectedPages.contains(thumb.pageIndex);
                return GestureDetector(
                  onTap: () => _togglePageSelection(thumb.pageIndex),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: selected ? AppTheme.primaryColor : Colors.grey.withValues(alpha: 0.3), width: selected ? 3 : 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(thumb.bytes, fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: selected ? AppTheme.primaryColor : Colors.black45,
                          child: Text('${thumb.pageIndex + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                        ),
                      ),
                      if (selected)
                        const Positioned(
                          bottom: 4,
                          right: 4,
                          child: CircleAvatar(radius: 10, backgroundColor: AppTheme.primaryColor, child: Icon(Icons.check, size: 14, color: Colors.white)),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_isLoadingPreview)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_previewImageBase64 != null)
              Center(
                child: Image.memory(
                  base64Decode(_previewImageBase64!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Text('Preview tidak tersedia'),
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Preview belum tersedia', style: TextStyle(color: Colors.grey[600])),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Helper kecil buat nyimpen hasil render thumbnail PDF beserta index
/// halaman aslinya (0-indexed).
class Uint8ListThumb {
  final int pageIndex;
  final Uint8List bytes;
  Uint8ListThumb({required this.pageIndex, required this.bytes});
}
