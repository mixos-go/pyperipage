import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../data/models/printer_models.dart';

/// Manual Crop Editor -- crop per halaman/gambar dengan drag interaktif,
/// dan bisa "Apply ke semua" / "Apply ke halaman terpilih" supaya tidak
/// perlu crop manual satu-satu kalau semua halaman punya layout serupa
/// (mis. label pengiriman Shopee/TikTok dari 1 PDF yang sama).
///
/// CATATAN: rect dari `onMoved` diasumsikan dalam koordinat PIXEL GAMBAR ASLI
/// (bukan koordinat viewport widget) -- ini konsisten dengan `initialArea`
/// milik package `crop_your_image` yang didokumentasikan "based on actual
/// image data". Kalau ternyata beda di device fisik, cukup sesuaikan fungsi
/// `_normalizedRectFor()` di bawah.
class ManualCropScreen extends StatefulWidget {
  /// Bytes gambar per halaman/file, urutan sesuai index yang dipakai di
  /// PrintScreen (0-based).
  final List<Uint8List> images;
  final List<String> labels; // label tiap halaman, mis. "Halaman 1", nama file
  final Map<int, CropRect> initialCrops;
  final int initialPageIndex;

  const ManualCropScreen({
    super.key,
    required this.images,
    required this.labels,
    this.initialCrops = const {},
    this.initialPageIndex = 0,
  });

  @override
  State<ManualCropScreen> createState() => _ManualCropScreenState();
}

class _ManualCropScreenState extends State<ManualCropScreen> {
  late final PageController _pageController;
  late int _currentPage;
  final Map<int, CropController> _controllers = {};
  final Map<int, Rect> _liveRects = {}; // rect pixel (image-based) hasil onMoved
  final Map<int, Size> _imageSizes = {};
  late final Map<int, CropRect> _savedCrops;
  bool _decodingSizes = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPageIndex;
    _savedCrops = Map<int, CropRect>.from(widget.initialCrops);
    _pageController = PageController(initialPage: _currentPage);
    for (int i = 0; i < widget.images.length; i++) {
      _controllers[i] = CropController();
    }
    _decodeAllImageSizes();
  }

  Future<void> _decodeAllImageSizes() async {
    for (int i = 0; i < widget.images.length; i++) {
      try {
        final codec = await ui.instantiateImageCodec(widget.images[i]);
        final frame = await codec.getNextFrame();
        _imageSizes[i] = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      } catch (_) {
        // Gagal decode ukuran -- fallback nanti pakai rect default full image.
      }
    }
    if (mounted) setState(() => _decodingSizes = false);
  }

  CropRect? _normalizedRectFor(int index) {
    final rect = _liveRects[index];
    final size = _imageSizes[index];
    if (rect == null || size == null || size.width <= 0 || size.height <= 0) return null;
    return CropRect(
      left: (rect.left / size.width).clamp(0.0, 1.0),
      top: (rect.top / size.height).clamp(0.0, 1.0),
      right: (rect.right / size.width).clamp(0.0, 1.0),
      bottom: (rect.bottom / size.height).clamp(0.0, 1.0),
    );
  }

  void _persistCurrentPageCrop() {
    final rect = _normalizedRectFor(_currentPage);
    if (rect != null) _savedCrops[_currentPage] = rect;
  }

  Rect? _initialAreaFor(int index) {
    final saved = _savedCrops[index];
    final size = _imageSizes[index];
    if (saved == null || size == null) return null;
    return Rect.fromLTRB(
      saved.left * size.width,
      saved.top * size.height,
      saved.right * size.width,
      saved.bottom * size.height,
    );
  }

  void _applyToAll() {
    _persistCurrentPageCrop();
    final rect = _savedCrops[_currentPage];
    if (rect == null) {
      _showSnack('Atur area crop dulu sebelum apply ke semua halaman.');
      return;
    }
    setState(() {
      for (int i = 0; i < widget.images.length; i++) {
        _savedCrops[i] = rect;
      }
    });
    _showSnack('Crop diterapkan ke semua ${widget.images.length} halaman.');
  }

  Future<void> _applyToSelected() async {
    _persistCurrentPageCrop();
    final rect = _savedCrops[_currentPage];
    if (rect == null) {
      _showSnack('Atur area crop dulu sebelum apply ke halaman lain.');
      return;
    }
    final selected = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => _PageSelectDialog(
        labels: widget.labels,
        excludeIndex: _currentPage,
      ),
    );
    if (selected == null || selected.isEmpty) return;
    setState(() {
      for (final i in selected) {
        _savedCrops[i] = rect;
      }
    });
    _showSnack('Crop diterapkan ke ${selected.length} halaman terpilih.');
  }

  void _resetCurrentPage() {
    setState(() {
      _savedCrops.remove(_currentPage);
      _liveRects.remove(_currentPage);
      _controllers[_currentPage] = CropController();
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _done() {
    _persistCurrentPageCrop();
    Navigator.pop(context, _savedCrops);
  }

  @override
  Widget build(BuildContext context) {
    final multiPage = widget.images.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          multiPage ? 'Manual Crop (${_currentPage + 1}/${widget.images.length})' : 'Manual Crop',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _done,
            child: const Text('SELESAI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _decodingSizes
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.images.length,
                    onPageChanged: (i) {
                      _persistCurrentPageCrop();
                      setState(() => _currentPage = i);
                    },
                    itemBuilder: (context, i) {
                      return Crop(
                        image: widget.images[i],
                        controller: _controllers[i]!,
                        initialArea: _initialAreaFor(i),
                        onMoved: (rect) => _liveRects[i] = rect,
                        onCropped: (result) {}, // hasil crop final dikerjakan backend, bukan di sini
                        baseColor: Colors.black,
                        maskColor: Colors.black.withValues(alpha: 0.6),
                        cornerDotBuilder: (size, edgeAlignment) => Container(
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppTheme.primaryGradient),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  color: const Color(0xFF1A1A1A),
                  padding: const EdgeInsets.all(UiConstants.spacingMd),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (multiPage)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _applyToAll,
                                icon: const Icon(Icons.select_all, color: Colors.white),
                                label: const Text('Apply Semua', style: TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38)),
                              ),
                            ),
                            const SizedBox(width: UiConstants.spacingSm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _applyToSelected,
                                icon: const Icon(Icons.checklist, color: Colors.white),
                                label: const Text('Apply Terpilih', style: TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38)),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: UiConstants.spacingSm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: _resetCurrentPage,
                            icon: const Icon(Icons.refresh, color: Colors.white70),
                            label: const Text('Reset', style: TextStyle(color: Colors.white70)),
                          ),
                          if (multiPage)
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                                  onPressed: _currentPage > 0
                                      ? () => _pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                                      : null,
                                ),
                                Text('${_currentPage + 1} / ${widget.images.length}', style: const TextStyle(color: Colors.white)),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                                  onPressed: _currentPage < widget.images.length - 1
                                      ? () => _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                                      : null,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PageSelectDialog extends StatefulWidget {
  final List<String> labels;
  final int excludeIndex;

  const _PageSelectDialog({required this.labels, required this.excludeIndex});

  @override
  State<_PageSelectDialog> createState() => _PageSelectDialogState();
}

class _PageSelectDialogState extends State<_PageSelectDialog> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Halaman Tujuan'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.labels.length,
          itemBuilder: (context, i) {
            if (i == widget.excludeIndex) return const SizedBox.shrink();
            return CheckboxListTile(
              value: _selected.contains(i),
              title: Text(widget.labels[i]),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selected.add(i);
                } else {
                  _selected.remove(i);
                }
              }),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        TextButton(onPressed: () => Navigator.pop(context, _selected), child: const Text('Terapkan')),
      ],
    );
  }
}
