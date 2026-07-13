import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../data/models/printer_models.dart';

/// Manual Crop Editor -- DIBANGUN SENDIRI dari widget Flutter dasar (bukan
/// package pihak ketiga) supaya perilaku resize/move 100% terkontrol &
/// tidak tergantung API package yang berubah-ubah antar versi (fix Juli
/// 2026: 2x percobaan pakai `crop_your_image` gagal karena versi API-nya
/// tidak sesuai dugaan, resize handle sama sekali tidak muncul di device).
///
/// Interaksi (mirip free-crop editor pada umumnya):
/// - Drag AREA TENGAH kotak crop -> geser posisi.
/// - Drag TITIK PUTIH DI POJOK -> resize (independen per pojok, bisa ubah
///   lebar & tinggi sekaligus atau salah satu saja tergantung pojok mana).
/// - "Apply Semua" / "Apply Terpilih" -- salin pola crop (rect ternormalisasi
///   0.0-1.0) dari halaman aktif ke halaman lain, TANPA perlu crop ulang
///   manual satu-satu.
class ManualCropScreen extends StatefulWidget {
  final List<Uint8List> images;
  final List<String> labels;
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
  late final Map<int, CropRect> _crops;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPageIndex;
    _crops = {
      for (int i = 0; i < widget.images.length; i++) i: widget.initialCrops[i] ?? CropRect.full,
    };
    _pageController = PageController(initialPage: _currentPage);
  }

  void _applyToAll() {
    final rect = _crops[_currentPage]!;
    setState(() {
      for (int i = 0; i < widget.images.length; i++) {
        _crops[i] = rect;
      }
    });
    _showSnack('Pola crop diterapkan ke semua ${widget.images.length} halaman.');
  }

  Future<void> _applyToSelected() async {
    final rect = _crops[_currentPage]!;
    final selected = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => _PageSelectDialog(labels: widget.labels, excludeIndex: _currentPage),
    );
    if (selected == null || selected.isEmpty) return;
    setState(() {
      for (final i in selected) {
        _crops[i] = rect;
      }
    });
    _showSnack('Pola crop diterapkan ke ${selected.length} halaman terpilih.');
  }

  void _resetCurrentPage() {
    setState(() => _crops[_currentPage] = CropRect.full);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _done() {
    // Cuma kembalikan halaman yang BENERAN di-crop (bukan full image) --
    // biar backend tidak crop percuma buat halaman yang tidak disentuh user.
    final result = <int, CropRect>{
      for (final entry in _crops.entries)
        if (!entry.value.isFullImage) entry.key: entry.value,
    };
    Navigator.pop(context, result);
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: UiConstants.spacingSm),
            child: Text(
              'Geser tengah kotak = pindah. Geser titik pojok = resize.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              // FIX (Juli 2026): swipe PageView DIMATIKAN -- sebelumnya
              // drag handle resize crop (terutama dekat tepi kiri/kanan)
              // berebut gesture arena dengan swipe PageView bawaan, bikin
              // resize kadang malah kepick sebagai "ganti halaman" atau
              // draggable jadi susah/tersendat. Navigasi antar halaman
              // sepenuhnya lewat tombol panah (sudah ada di toolbar bawah),
              // jadi swipe tidak dibutuhkan & aman dihilangkan sepenuhnya.
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, i) {
                return _CropEditor(
                  imageBytes: widget.images[i],
                  rect: _crops[i]!,
                  onChanged: (r) => setState(() => _crops[i] = r),
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

/// Editor crop untuk SATU gambar -- render gambar (BoxFit.contain, jadi bisa
/// ada letterbox kiri-kanan/atas-bawah), lalu overlay kotak crop yang bisa
/// digeser & di-resize lewat 4 titik pojok. Semua matematika koordinat
/// (letterbox offset, konversi pixel<->fraksi) dihitung manual di sini --
/// tidak ada dependency ke package pihak ketiga sama sekali.
class _CropEditor extends StatefulWidget {
  final Uint8List imageBytes;
  final CropRect rect; // fraksi 0.0-1.0 relatif ke gambar ASLI
  final ValueChanged<CropRect> onChanged;

  const _CropEditor({required this.imageBytes, required this.rect, required this.onChanged});

  @override
  State<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  ui.Image? _decoded;
  static const double _handleSize = 28; // ukuran visual (dot gradient)
  static const double _handleTouchTarget = 48; // area SENTUH -- standar Material touch target minimum, jauh lebih besar dari visual biar tidak "susah di-drag"
  static const double _minCropFraction = 0.08; // area crop minimal 8% dari lebar/tinggi gambar

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(covariant _CropEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageBytes != widget.imageBytes) _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _decoded = frame.image);
  }

  /// Hitung rect gambar yang benar-benar dirender (BoxFit.contain) di dalam
  /// [containerSize], termasuk offset letterbox-nya.
  Rect _imageRenderRect(Size containerSize) {
    final img = _decoded!;
    final imgSize = Size(img.width.toDouble(), img.height.toDouble());
    final scale = (containerSize.width / imgSize.width < containerSize.height / imgSize.height)
        ? containerSize.width / imgSize.width
        : containerSize.height / imgSize.height;
    final renderedW = imgSize.width * scale;
    final renderedH = imgSize.height * scale;
    final offsetX = (containerSize.width - renderedW) / 2;
    final offsetY = (containerSize.height - renderedH) / 2;
    return Rect.fromLTWH(offsetX, offsetY, renderedW, renderedH);
  }

  void _updateRectFromWidgetSpace(Rect imageRenderRect, Rect newWidgetRect) {
    // Clamp ke batas gambar (tidak boleh keluar area render).
    final clamped = Rect.fromLTRB(
      newWidgetRect.left.clamp(imageRenderRect.left, imageRenderRect.right),
      newWidgetRect.top.clamp(imageRenderRect.top, imageRenderRect.bottom),
      newWidgetRect.right.clamp(imageRenderRect.left, imageRenderRect.right),
      newWidgetRect.bottom.clamp(imageRenderRect.top, imageRenderRect.bottom),
    );
    final normalized = CropRect(
      left: ((clamped.left - imageRenderRect.left) / imageRenderRect.width).clamp(0.0, 1.0),
      top: ((clamped.top - imageRenderRect.top) / imageRenderRect.height).clamp(0.0, 1.0),
      right: ((clamped.right - imageRenderRect.left) / imageRenderRect.width).clamp(0.0, 1.0),
      bottom: ((clamped.bottom - imageRenderRect.top) / imageRenderRect.height).clamp(0.0, 1.0),
    );
    widget.onChanged(normalized);
  }

  @override
  Widget build(BuildContext context) {
    if (_decoded == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imageRenderRect = _imageRenderRect(containerSize);

        // Rect crop dalam koordinat WIDGET (pixel layar), hasil konversi dari
        // fraksi 0.0-1.0 (source of truth) + offset letterbox gambar.
        final cropWidgetRect = Rect.fromLTRB(
          imageRenderRect.left + widget.rect.left * imageRenderRect.width,
          imageRenderRect.top + widget.rect.top * imageRenderRect.height,
          imageRenderRect.left + widget.rect.right * imageRenderRect.width,
          imageRenderRect.top + widget.rect.bottom * imageRenderRect.height,
        );

        final minSizePx = _minCropFraction * imageRenderRect.shortestSide;

        return Stack(
          children: [
            // Gambar asli, dirender pas di area yang sudah dihitung (BoxFit.contain).
            Positioned.fromRect(
              rect: imageRenderRect,
              child: Image.memory(widget.imageBytes, fit: BoxFit.fill),
            ),
            // Mask gelap di LUAR area crop -- pakai 4 potongan Positioned
            // (atas/bawah/kiri/kanan) daripada CustomPainter, lebih sederhana.
            _buildMaskOverlay(containerSize, cropWidgetRect),
            // Border kotak crop.
            Positioned.fromRect(
              rect: cropWidgetRect,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2)),
                ),
              ),
            ),
            // Drag area TENGAH -- geser posisi kotak (tanpa ubah ukuran).
            Positioned.fromRect(
              rect: cropWidgetRect.deflate(_handleTouchTarget / 2),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanUpdate: (details) {
                  final shifted = cropWidgetRect.shift(details.delta);
                  // Kalau hasil geser bikin rect keluar batas gambar, jangan
                  // geser sama sekali di sumbu itu (daripada rect ke-resize
                  // paksa oleh clamp di _updateRectFromWidgetSpace).
                  if (shifted.left < imageRenderRect.left || shifted.right > imageRenderRect.right) {
                    return;
                  }
                  _updateRectFromWidgetSpace(imageRenderRect, shifted);
                },
              ),
            ),
            // 4 handle pojok -- masing-masing resize independen.
            _cornerHandle(
              center: cropWidgetRect.topLeft,
              onDrag: (delta) {
                final newRect = Rect.fromLTRB(
                  (cropWidgetRect.left + delta.dx).clamp(imageRenderRect.left, cropWidgetRect.right - minSizePx),
                  (cropWidgetRect.top + delta.dy).clamp(imageRenderRect.top, cropWidgetRect.bottom - minSizePx),
                  cropWidgetRect.right,
                  cropWidgetRect.bottom,
                );
                _updateRectFromWidgetSpace(imageRenderRect, newRect);
              },
            ),
            _cornerHandle(
              center: cropWidgetRect.topRight,
              onDrag: (delta) {
                final newRect = Rect.fromLTRB(
                  cropWidgetRect.left,
                  (cropWidgetRect.top + delta.dy).clamp(imageRenderRect.top, cropWidgetRect.bottom - minSizePx),
                  (cropWidgetRect.right + delta.dx).clamp(cropWidgetRect.left + minSizePx, imageRenderRect.right),
                  cropWidgetRect.bottom,
                );
                _updateRectFromWidgetSpace(imageRenderRect, newRect);
              },
            ),
            _cornerHandle(
              center: cropWidgetRect.bottomLeft,
              onDrag: (delta) {
                final newRect = Rect.fromLTRB(
                  (cropWidgetRect.left + delta.dx).clamp(imageRenderRect.left, cropWidgetRect.right - minSizePx),
                  cropWidgetRect.top,
                  cropWidgetRect.right,
                  (cropWidgetRect.bottom + delta.dy).clamp(cropWidgetRect.top + minSizePx, imageRenderRect.bottom),
                );
                _updateRectFromWidgetSpace(imageRenderRect, newRect);
              },
            ),
            _cornerHandle(
              center: cropWidgetRect.bottomRight,
              onDrag: (delta) {
                final newRect = Rect.fromLTRB(
                  cropWidgetRect.left,
                  cropWidgetRect.top,
                  (cropWidgetRect.right + delta.dx).clamp(cropWidgetRect.left + minSizePx, imageRenderRect.right),
                  (cropWidgetRect.bottom + delta.dy).clamp(cropWidgetRect.top + minSizePx, imageRenderRect.bottom),
                );
                _updateRectFromWidgetSpace(imageRenderRect, newRect);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildMaskOverlay(Size containerSize, Rect cropRect) {
    final maskColor = Colors.black.withValues(alpha: 0.65);
    return IgnorePointer(
      child: Stack(
        children: [
          // Atas
          Positioned(left: 0, top: 0, right: 0, height: cropRect.top, child: Container(color: maskColor)),
          // Bawah
          Positioned(left: 0, top: cropRect.bottom, right: 0, bottom: 0, child: Container(color: maskColor)),
          // Kiri
          Positioned(left: 0, top: cropRect.top, width: cropRect.left, height: cropRect.height, child: Container(color: maskColor)),
          // Kanan
          Positioned(left: cropRect.right, top: cropRect.top, right: 0, height: cropRect.height, child: Container(color: maskColor)),
        ],
      ),
    );
  }

  Widget _cornerHandle({required Offset center, required ValueChanged<Offset> onDrag}) {
    return Positioned(
      left: center.dx - _handleTouchTarget / 2,
      top: center.dy - _handleTouchTarget / 2,
      width: _handleTouchTarget,
      height: _handleTouchTarget,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDrag(details.delta),
        child: Center(
          child: Container(
            width: _handleSize,
            height: _handleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.primaryGradient,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
            ),
          ),
        ),
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
