import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/printer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';

/// Settings Screen - Pengaturan printer & informasi aplikasi.
///
/// Sebelumnya file ini cuma placeholder ("Segera hadir") walaupun
/// PrinterProvider sudah punya semua kemampuan yang dibutuhkan
/// (setPaperWidth, status koneksi, disconnect) -- jadi UI-nya dilengkapi
/// di sini, TANPA menambah logic baru di provider/backend selain
/// `disconnect()` yang memang belum di-expose sebelumnya.
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(UiConstants.spacingMd),
        children: [
          // Status Koneksi
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.isConnected ? 'Terhubung' : 'Tidak terhubung',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (provider.isConnected)
                              Text(
                                'Via ${provider.printerStatus?.transportType.toUpperCase() ?? '-'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
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

          // Tentang Aplikasi
          Card(
            child: Padding(
              padding: const EdgeInsets.all(UiConstants.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tentang', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: UiConstants.spacingMd),
                  const _InfoRow(label: 'Aplikasi', value: 'PeriPage A9'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiConstants.spacingXs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
