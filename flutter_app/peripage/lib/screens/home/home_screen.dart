import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/printer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../print/print_screen.dart';
import '../settings/settings_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrinterProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PeriPage A9'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              provider.loadPrinterStatus();
              provider.loadPrinterConfig();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.loadPrinterStatus();
          await provider.loadPrinterConfig();
        },
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
                    ? Icons.print_connected 
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
                  color: AppTheme.warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(UiConstants.borderRadiusMd),
                  border: Border.all(color: AppTheme.warningColor),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(width: UiConstants.spacingSm),
                    Expanded(
                      child: Text(
                        'Python backend tidak tersedia. Pastikan server berjalan di port 8000.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.warningColor,
                        ),
                      ),
                    ),
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
                    onPressed: provider.isLoading ? null : () => provider.connectUsb(),
                    icon: const Icon(Icons.usb),
                    label: const Text('USB'),
                  ),
                ),
                const SizedBox(width: UiConstants.spacingSm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: provider.isLoading ? null : () => provider.connectBle(),
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
            // Navigate to print screen with image mode
          },
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.picture_as_pdf,
          title: 'Print PDF',
          subtitle: 'Resi & Label',
          onTap: () {
            // Navigate to print screen with PDF mode
          },
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.folder_open,
          title: 'Batch Print',
          subtitle: 'Multiple files',
          onTap: () {
            // Navigate to print screen with batch mode
          },
        ),
        _buildQuickActionCard(
          context,
          icon: Icons.scan,
          title: 'Scan BLE',
          subtitle: 'Cari device',
          onTap: () {
            provider.discoverBleDevices();
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
