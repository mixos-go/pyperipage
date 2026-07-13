import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/printer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/constants.dart';
import '../logs/log_viewer_screen.dart';
import '../ble/ble_scan_screen.dart';

/// Settings Screen - Pengaturan printer & informasi aplikasi.
///
/// REBUILD (Juli 2026): tambah info device terhubung (nama, address/UUID,
/// transport type) + tombol connect USB/BLE langsung dari Settings (dulu
/// cuma bisa dari Home), dan pemilih tema (Light/Dark/AMOLED).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _handleDisconnect(BuildContext context, PrinterProvider provider) async {
    final success = await provider.disconnect();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Printer diputus.' : (provider.errorMessage ?? 'Gagal memutus koneksi.')),
        backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );
  }

  Future<void> _handleConnectUsb(BuildContext context, PrinterProvider provider) async {
    final success = await provider.connectUsb();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Terhubung via USB.' : (provider.errorMessage ?? 'Gagal terhubung via USB.')),
        backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );
  }

  Future<void> _handleScanBle(BuildContext context, PrinterProvider provider) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const BleScanScreen()));
  }

  Future<void> _handleSetPaperWidth(BuildContext context, PrinterProvider provider, int width) async {
    final success = await provider.setPaperWidth(width);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Lebar kertas diset ke $width mm.' : (provider.errorMessage ?? 'Gagal mengubah lebar kertas.'),
        ),
        backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrinterProvider>();
    final themeController = context.watch<ThemeController>();
    final status = provider.printerStatus;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(UiConstants.spacingMd),
        children: [
          // Status Koneksi + Info Device Terhubung
          Card(
            child: Padding(
              padding: const EdgeInsets.all(UiConstants.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Koneksi Printer', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiConstants.spacingMd),
                  Row(
                    children: [
                      Icon(
                        provider.isConnected ? Icons.print : Icons.print_disabled,
                        color: provider.isConnected ? AppTheme.successColor : AppTheme.errorColor,
                      ),
                      const SizedBox(width: UiConstants.spacingSm),
                      Expanded(
                        child: Text(
                          provider.isConnected ? 'Terhubung' : 'Tidak terhubung',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (provider.isConnected)
                        TextButton.icon(
                          onPressed: provider.isLoading ? null : () => _handleDisconnect(context, provider),
                          icon: const Icon(Icons.link_off, color: AppTheme.errorColor),
                          label: const Text('Putuskan', style: TextStyle(color: AppTheme.errorColor)),
                        ),
                    ],
                  ),
                  if (provider.isConnected && status != null) ...[
                    const Divider(height: UiConstants.spacingLg),
                    _InfoRow(label: 'Nama Device', value: status.deviceName ?? '-'),
                    const SizedBox(height: 6),
                    _InfoRow(label: 'Address / UUID', value: status.deviceAddress ?? '(USB tidak punya address)'),
                    const SizedBox(height: 6),
                    _InfoRow(label: 'Transport', value: status.transportType.toUpperCase()),
                    const SizedBox(height: 6),
                    _InfoRow(label: 'Lebar Kertas Aktif', value: '${status.paperWidthMm} mm'),
                  ],
                  if (!provider.isConnected) ...[
                    const SizedBox(height: UiConstants.spacingMd),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: provider.isLoading ? null : () => _handleConnectUsb(context, provider),
                            icon: const Icon(Icons.usb),
                            label: const Text('USB'),
                          ),
                        ),
                        const SizedBox(width: UiConstants.spacingSm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: provider.isLoading ? null : () => _handleScanBle(context, provider),
                            icon: const Icon(Icons.bluetooth),
                            label: const Text('BLE'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: UiConstants.spacingMd),

          // Lebar Kertas
          Card(
            child: Padding(
              padding: const EdgeInsets.all(UiConstants.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lebar Kertas Default', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiConstants.spacingXs),
                  Text(
                    'Berlaku untuk semua cetak berikutnya kalau tidak dipilih manual.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: UiConstants.spacingMd),
                  if (provider.printerConfig != null)
                    Wrap(
                      spacing: UiConstants.spacingSm,
                      children: provider.printerConfig!.supportedPaperWidths.map((width) {
                        final selected = width == provider.printerConfig!.currentPaperWidth;
                        return ChoiceChip(
                          label: Text('$width mm'),
                          selected: selected,
                          onSelected: provider.isLoading || selected
                              ? null
                              : (_) => _handleSetPaperWidth(context, provider, width),
                        );
                      }).toList(),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: UiConstants.spacingSm),
                      child: Text('Memuat konfigurasi...'),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: UiConstants.spacingMd),

          // Protokol Cetak (Lanjutan) -- override manual RAW/COMPRESSED.
          // Lihat PERIPAGE_PROTOCOL.md (hasil reverse-engineering app
          // resmi PeriPage, Juli 2026): printer generasi baru (A9 dst)
          // sebenarnya pakai bitmap TERKOMPRESI (zlib), bukan RAW seperti
          // yang sejauh ini dipakai app ini untuk semua device. Auto-detect
          // cuma jalan kalau nama device COCOK PERSIS daftar resmi -- untuk
          // device dengan nama custom/varian (mis. "..._BLE"), user bisa
          // paksa manual di sini & verifikasi sendiri mana yang benar.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(UiConstants.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Protokol Cetak (Lanjutan)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiConstants.spacingXs),
                  Text(
                    'Auto biasanya sudah benar. Kalau hasil cetak terlihat rusak/blank, '
                    'coba paksa mode lain di sini untuk device kamu.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (provider.isConnected && status?.detectedProtocol != null) ...[
                    const SizedBox(height: UiConstants.spacingSm),
                    Text(
                      'Terdeteksi otomatis untuk device ini: ${status!.detectedProtocol!.toUpperCase()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: UiConstants.spacingMd),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'auto', label: Text('Auto')),
                      ButtonSegment(value: 'raw', label: Text('RAW')),
                      ButtonSegment(value: 'compressed', label: Text('Compressed')),
                    ],
                    selected: {provider.protocolOverride ?? 'auto'},
                    onSelectionChanged: (selection) {
                      final value = selection.first;
                      provider.setProtocolOverride(value == 'auto' ? null : value);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: UiConstants.spacingMd),

          // Tema
          Card(
            child: Padding(
              padding: const EdgeInsets.all(UiConstants.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tampilan', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiConstants.spacingMd),
                  SegmentedButton<AppThemeMode>(
                    segments: const [
                      ButtonSegment(value: AppThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                      ButtonSegment(value: AppThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                      ButtonSegment(value: AppThemeMode.amoled, label: Text('AMOLED'), icon: Icon(Icons.nightlight)),
                    ],
                    selected: {themeController.mode},
                    onSelectionChanged: (modes) => themeController.setMode(modes.first),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: UiConstants.spacingMd),

          // Log Aplikasi -- lihat & export semua log sesi (koneksi, error
          // native call, backend desktop, dll) TANPA perlu adb logcat.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(UiConstants.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Log Aplikasi', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiConstants.spacingXs),
                  Text(
                    'Untuk keperluan debugging -- lihat & export log sesi ini kalau ada masalah.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: UiConstants.spacingMd),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const LogViewerScreen()));
                      },
                      icon: const Icon(Icons.article_outlined),
                      label: const Text('Lihat Log'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: UiConstants.spacingMd),

          // Tentang Aplikasi
          Card(
            child: Padding(
              padding: const EdgeInsets.all(UiConstants.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tentang', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiConstants.spacingMd),
                  const _InfoRow(label: 'Aplikasi', value: 'PyPeriPage'),
                  const Divider(),
                  const _InfoRow(label: 'Versi', value: '1.0.0'),
                  const Divider(),
                  _InfoRow(
                    label: 'PDF Support',
                    value: (provider.printerConfig?.pdfSupport ?? false) ? 'Ya' : 'Tidak',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(width: UiConstants.spacingSm),
        Flexible(
          child: SelectableText(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
