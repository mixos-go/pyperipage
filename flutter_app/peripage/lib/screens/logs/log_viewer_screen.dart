import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/constants.dart';

/// Layar log aplikasi -- menampilkan semua log yang tercatat sepanjang
/// sesi (koneksi USB/BLE, backend desktop, error native call, dst) dan bisa
/// di-export/share langsung dari device, TANPA perlu adb logcat atau
/// sambungan komputer sama sekali.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  Future<void> _exportLog() async {
    final text = AppLogger.instance.exportAsText();
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'PeriPage A9 - Log Aplikasi'),
    );
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Log?'),
        content: const Text('Semua log yang tercatat di sesi ini akan dihapus. Lanjutkan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              setState(() => AppLogger.instance.clear());
              Navigator.pop(dialogContext);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = AppLogger.instance.entries.reversed.toList(); // terbaru duluan

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Aplikasi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Hapus log',
            onPressed: entries.isEmpty ? null : _confirmClear,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export / Share log',
            onPressed: _exportLog,
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(UiConstants.spacingLg),
                child: Text(
                  'Belum ada log tercatat di sesi ini.\nCoba lakukan aksi (connect, print, dll) lalu kembali ke sini.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(UiConstants.spacingSm),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final isError = entry.message.contains('❌') || entry.message.toLowerCase().contains('error');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(
                    entry.toString(),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isError ? Colors.red.shade700 : null,
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exportLog,
        icon: const Icon(Icons.ios_share),
        label: const Text('Export Log'),
      ),
    );
  }
}
