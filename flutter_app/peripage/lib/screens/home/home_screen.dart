import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import '../../providers/printer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/constants.dart';
import '../../core/services/recent_files_service.dart';
import '../print/print_screen.dart';
import '../settings/settings_screen.dart';
import '../logs/log_viewer_screen.dart';
import '../ble/ble_scan_screen.dart';
import '../../services/desktop_backend_service.dart';
import '../../widgets/circle_nav_bar.dart';
import '../../widgets/printer_status_header.dart';

/// App Shell -- root navigasi aplikasi PyPeriPage.
/// Nav bawah custom (CircleNavBar): [Settings] [Print - circle] [Workspace].
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const WorkspaceScreen(),
    const PrintScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterProvider>().checkServerAvailability();
      context.read<PrinterProvider>().loadPrinterStatus();
      context.read<PrinterProvider>().loadPrinterConfig();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: CircleNavBar(
        selectedIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

/// Workspace (sebelumnya "HomeTab") -- dashboard utama gaya "AI workspace":
/// header status printer animasi, drawer navigasi, recent files, quick
/// actions, dan info printer.
class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({super.key});

  Future<void> _handleRefresh(BuildContext context, PrinterProvider provider) async {
    await provider.checkServerAvailability();
    await provider.loadPrinterStatus();
    await provider.loadPrinterConfig();
    if (!context.mounted) return;
    if (provider.errorMessage != null) {
      _showSnackBar(context, provider.errorMessage!, isError: true, details: provider.errorDetails);
    }
  }

  Future<void> _handleConnectUsb(BuildContext context, PrinterProvider provider) async {
    final success = await provider.connectUsb();
    if (!context.mounted) return;
    if (success) {
      _showSnackBar(context, 'Terhubung ke printer via USB.');
    } else {
      _showSnackBar(context, provider.errorMessage ?? 'Gagal terhubung via USB.', isError: true, details: provider.errorDetails);
    }
  }

  Future<void> _handleScanBle(BuildContext context, PrinterProvider provider) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const BleScanScreen()));
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false, String? details}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
        action: (isError && details != null && details.isNotEmpty)
            ? SnackBarAction(
                label: 'Lihat Detail',
                textColor: Colors.white,
                onPressed: () => _showErrorDetailDialog(context, message, details),
              )
            : null,
      ),
    );
  }

  void _showErrorDetailDialog(BuildContext context, String message, String details) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Detail Error'),
        content: SingleChildScrollView(child: SelectableText('$message\n\n$details')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrinterProvider>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: PrinterStatusHeader(
          isConnected: provider.isConnected,
          deviceName: provider.printerStatus?.deviceName,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _handleRefresh(context, provider)),
        ],
      ),
      drawer: const _WorkspaceDrawer(),
      body: RefreshIndicator(
        onRefresh: () => _handleRefresh(context, provider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(UiConstants.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusCard(context, provider),
              const SizedBox(height: UiConstants.spacingLg),
              Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: UiConstants.spacingMd),
              _buildQuickActions(context, provider),
              const SizedBox(height: UiConstants.spacingLg),
              _buildRecentFilesSection(context, provider),
              const SizedBox(height: UiConstants.spacingLg),
              _buildInfoCard(context, provider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, PrinterProvider provider) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
        gradient: provider.isConnected
            ? LinearGradient(
                colors: [AppTheme.successColor.withValues(alpha: 0.12), Colors.transparent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: provider.isConnected ? null : Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (provider.isConnected ? AppTheme.successColor : AppTheme.errorColor).withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    provider.isConnected ? Icons.print : Icons.print_disabled,
                    color: provider.isConnected ? AppTheme.successColor : AppTheme.errorColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: UiConstants.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.isConnected ? 'Printer Terhubung' : 'Tidak Terhubung',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: provider.isConnected ? AppTheme.successColor : AppTheme.errorColor,
                            ),
                      ),
                      const SizedBox(height: UiConstants.spacingXs),
                      Text(
                        provider.printerStatus?.message ?? 'Memeriksa status...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!provider.isServerAvailable) ...[
              const SizedBox(height: UiConstants.spacingMd),
              Container(
                padding: const EdgeInsets.all(UiConstants.spacingMd),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(UiConstants.borderRadiusMd),
                  border: Border.all(color: AppTheme.warningColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor),
                        const SizedBox(width: UiConstants.spacingSm),
                        Expanded(
                          child: Text(
                            provider.errorMessage ?? 'Python backend tidak tersedia. Pastikan server berjalan di port 8000.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.warningColor),
                          ),
                        ),
                      ],
                    ),
                    if (DesktopBackendService().isDesktop) ...[
                      const SizedBox(height: UiConstants.spacingSm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: provider.isLoading
                              ? null
                              : () async {
                                  final ok = await provider.retryBackend();
                                  if (!context.mounted) return;
                                  if (ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Backend berhasil dijalankan ulang.'), backgroundColor: AppTheme.successColor),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Coba Jalankan Ulang Backend'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, PrinterProvider provider) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: UiConstants.spacingMd,
      crossAxisSpacing: UiConstants.spacingMd,
      children: [
        _buildQuickActionCard(
          context,
          icon: Icons.image,
          title: 'Print Gambar',
          subtitle: 'Dari gallery',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrintScreen())),
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.picture_as_pdf,
          title: 'Print PDF',
          subtitle: 'Resi & Label',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrintScreen())),
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.folder_open,
          title: 'Batch Print',
          subtitle: 'Multiple files',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrintScreen(initialBatchMode: true))),
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.bluetooth_searching,
          title: 'Scan BLE',
          subtitle: 'Cari device',
          onTap: () => _handleScanBle(context, provider),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
        side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
        child: Padding(
          padding: const EdgeInsets.all(UiConstants.spacingMd),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                ),
                child: Icon(icon, size: 24, color: Colors.white),
              ),
              const SizedBox(height: UiConstants.spacingSm),
              Text(title, style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
              const SizedBox(height: UiConstants.spacingXs),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentFilesSection(BuildContext context, PrinterProvider provider) {
    final files = provider.recentFiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Files', style: Theme.of(context).textTheme.titleLarge),
            if (files.isNotEmpty)
              TextButton(
                onPressed: () => provider.clearRecentFiles(),
                child: const Text('Hapus'),
              ),
          ],
        ),
        const SizedBox(height: UiConstants.spacingSm),
        if (files.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: UiConstants.spacingLg),
              child: Column(
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Lottie.asset(
                      'assets/lottie/empty_state_float.json',
                      errorBuilder: (c, e, s) => const Icon(Icons.insert_drive_file_outlined, size: 48, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: UiConstants.spacingSm),
                  Text(
                    'Belum ada file yang di-print.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          )
        else
          ...files.map((f) => _buildRecentFileTile(context, f)),
      ],
    );
  }

  Widget _buildRecentFileTile(BuildContext context, RecentFile file) {
    final icon = switch (file.type) {
      'pdf' => Icons.picture_as_pdf,
      'batch' => Icons.folder_open,
      _ => Icons.image,
    };
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: UiConstants.spacingSm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.borderRadiusMd),
        side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_formatRelativeTime(file.printedAt)),
      ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inHours < 1) return '${diff.inMinutes} menit lalu';
    if (diff.inDays < 1) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }

  Widget _buildInfoCard(BuildContext context, PrinterProvider provider) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.borderRadiusLg),
        side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Informasi Printer', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: UiConstants.spacingMd),
            _buildInfoRow(context, label: 'Transport', value: provider.printerStatus?.transportType.toUpperCase() ?? '-'),
            const Divider(),
            _buildInfoRow(context, label: 'Lebar Kertas', value: '${provider.printerStatus?.paperWidthMm ?? 0} mm'),
            const Divider(),
            _buildInfoRow(context, label: 'PDF Support', value: provider.printerConfig?.pdfSupport ?? false ? 'Yes' : 'No'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, {required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

/// Drawer Workspace -- akses cepat ke Logs, About, dan pilihan tema.
class _WorkspaceDrawer extends StatelessWidget {
  const _WorkspaceDrawer();

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    right: -60,
                    top: -60,
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: Opacity(
                        opacity: 0.25,
                        child: Lottie.asset(
                          'assets/lottie/gradient_blob_bg.json',
                          errorBuilder: (c, e, s) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(UiConstants.spacingLg),
                    decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.print, color: AppTheme.primaryColor, size: 28),
                        ),
                        SizedBox(height: UiConstants.spacingSm),
                        Text('PyPeriPage', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('PeriPage A9 Printer', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Log Aplikasi'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LogViewerScreen()));
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: UiConstants.spacingMd, vertical: UiConstants.spacingSm),
              child: Text('Tema', style: Theme.of(context).textTheme.titleSmall),
            ),
            RadioGroup<AppThemeMode>(
              groupValue: themeController.mode,
              onChanged: (m) => themeController.setMode(m!),
              child: const Column(
                children: [
                  RadioListTile<AppThemeMode>(
                    value: AppThemeMode.light,
                    title: Text('Light'),
                  ),
                  RadioListTile<AppThemeMode>(
                    value: AppThemeMode.dark,
                    title: Text('Dark'),
                  ),
                  RadioListTile<AppThemeMode>(
                    value: AppThemeMode.amoled,
                    title: Text('AMOLED'),
                    subtitle: Text('Hitam murni, hemat daya OLED'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
