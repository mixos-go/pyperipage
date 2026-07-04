import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/printer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../print/print_screen.dart';
import '../settings/settings_screen.dart';
import '../../services/desktop_backend_service.dart';

/// Home Screen - Main dashboard aplikasi PeriPage A9
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeTab(),
    const PrintScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Check server availability on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterProvider>().checkServerAvailability();
      context.read<PrinterProvider>().loadPrinterStatus();
      context.read<PrinterProvider>().loadPrinterConfig();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.print_outlined),
            selectedIcon: Icon(Icons.print),
            label: 'Print',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Home Tab - Menampilkan status printer dan quick actions
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  Future<void> _handleRefresh(BuildContext context, PrinterProvider provider) async {
    await provider.checkServerAvailability();
    await provider.loadPrinterStatus();
    await provider.loadPrinterConfig();
    if (!context.mounted) return;
    if (provider.errorMessage != null) {
      _showSnackBar(context, provider.errorMessage!, isError: true);
    }
  }

  Future<void> _handleConnectUsb(BuildContext context, PrinterProvider provider) async {
    final success = await provider.connectUsb();
    if (!context.mounted) return;
    if (success) {
      _showSnackBar(context, 'Terhubung ke printer via USB.');
    } else {
      _showSnackBar(context, provider.errorMessage ?? 'Gagal terhubung via USB.', isError: true);
    }
  }

  Future<void> _handleScanBle(BuildContext context, PrinterProvider provider) async {
    await provider.discoverBleDevices();
    if (!context.mounted) return;
    if (provider.errorMessage != null) {
      _showSnackBar(context, provider.errorMessage!, isError: true);
      return;
    }
    if (provider.bleDevices.isEmpty) {
      _showSnackBar(context, 'Tidak ada device BLE ditemukan di sekitar.');
      return;
    }
    _showBleDevicePicker(context, provider);
  }

  void _showBleDevicePicker(BuildContext context, PrinterProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(UiConstants.spacingMd),
              child: Text(
                'Pilih Printer BLE',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ...provider.bleDevices.map((device) => ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(device.name),
                  subtitle: Text(device.address),
                  trailing: device.rssi != null ? Text('${device.rssi} dBm') : null,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final success = await provider.connectBle(deviceAddress: device.address);
                    if (!context.mounted) return;
                    if (success) {
                      _showSnackBar(context, 'Terhubung ke ${device.name}.');
                    } else {
                      _showSnackBar(
                        context,
                        provider.errorMessage ?? 'Gagal terhubung ke ${device.name}.',
                        isError: true,
                      );
                    }
                  },
                )),
            const SizedBox(height: UiConstants.spacingMd),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrinterProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PeriPage A9'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _handleRefresh(context, provider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _handleRefresh(context, provider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(UiConstants.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Card
              _buildStatusCard(context, provider),
              
              const SizedBox(height: UiConstants.spacingLg),
              
              // Quick Actions
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: UiConstants.spacingMd),
              _buildQuickActions(context, provider),
              
              const SizedBox(height: UiConstants.spacingLg),
              
              // Info Card
              _buildInfoCard(context, provider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, PrinterProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  provider.isConnected 
                    ? Icons.print 
                    : Icons.print_disabled,
                  color: provider.isConnected 
                    ? AppTheme.successColor 
                    : AppTheme.errorColor,
                  size: 32,
                ),
                const SizedBox(width: UiConstants.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.isConnected ? 'Printer Terhubung' : 'Tidak Terhubung',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: provider.isConnected 
                            ? AppTheme.successColor 
                            : AppTheme.errorColor,
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
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppTheme.warningColor,
                        ),
                        const SizedBox(width: UiConstants.spacingSm),
                        Expanded(
                          child: Text(
                            // Tampilkan alasan ASLI (exit code, stderr backend,
                            // dst dari provider.errorMessage) -- BUKAN pesan
                            // generik statis yang tidak menjelaskan apa-apa.
                            provider.errorMessage ??
                                'Python backend tidak tersedia. Pastikan server berjalan di port 8000.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.warningColor,
                            ),
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
                                      const SnackBar(
                                        content: Text('Backend berhasil dijalankan ulang.'),
                                        backgroundColor: AppTheme.successColor,
                                      ),
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
            
            // Connection buttons
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
                    // Connect BLE "buta" (tanpa address) sudah tidak didukung lagi
                    // sejak BLE jadi universal (bisa ke printer merk apa pun, bukan
                    // cuma yang bernama "PeriPage") -- device_address WAJIB dipilih
                    // dulu lewat scan, makanya tombol ini pakai alur yang sama
                    // dengan Quick Action "Scan BLE".
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
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrintScreen()),
            );
          },
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.picture_as_pdf,
          title: 'Print PDF',
          subtitle: 'Resi & Label',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrintScreen()),
            );
          },
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.folder_open,
          title: 'Batch Print',
          subtitle: 'Multiple files',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrintScreen(initialBatchMode: true)),
            );
          },
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.bluetooth_searching,
          title: 'Scan BLE',
          subtitle: 'Cari device',
          onTap: () {
            _handleScanBle(context, provider);
          },
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
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.borderRadiusMd),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UiConstants.borderRadiusMd),
        child: Padding(
          padding: const EdgeInsets.all(UiConstants.spacingMd),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 40,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: UiConstants.spacingSm),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: UiConstants.spacingXs),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, PrinterProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiConstants.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Informasi Printer',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: UiConstants.spacingMd),
            _buildInfoRow(
              context,
              label: 'Transport',
              value: provider.printerStatus?.transportType.toUpperCase() ?? '-',
            ),
            const Divider(),
            _buildInfoRow(
              context,
              label: 'Lebar Kertas',
              value: '${provider.printerStatus?.paperWidthMm ?? 0} mm',
            ),
            const Divider(),
            _buildInfoRow(
              context,
              label: 'PDF Support',
              value: provider.printerConfig?.pdfSupport ?? false ? 'Yes' : 'No',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, {required String label, required String value}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
