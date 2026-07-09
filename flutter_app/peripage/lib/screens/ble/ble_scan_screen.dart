import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import '../../providers/printer_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../data/models/printer_models.dart';

/// Layar khusus scan & connect printer BLE -- menampilkan SEMUA device yang
/// terpindai (bukan cuma bottom sheet singkat), dengan info sinyal (RSSI),
/// status scanning realtime, dan retry/refresh.
class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  bool _scanning = false;
  String? _connectingAddress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final provider = context.read<PrinterProvider>();
    await provider.discoverBleDevices();
    if (!mounted) return;
    setState(() => _scanning = false);
    if (provider.errorMessage != null) {
      _showSnack(provider.errorMessage!, isError: true);
    }
  }

  Future<void> _connect(BleDevice device) async {
    setState(() => _connectingAddress = device.address);
    final provider = context.read<PrinterProvider>();
    final success = await provider.connectBle(deviceAddress: device.address, deviceName: device.name);
    if (!mounted) return;
    setState(() => _connectingAddress = null);
    if (success) {
      _showSnack('Terhubung ke ${device.name}.');
      Navigator.pop(context, true);
    } else {
      _showSnack(provider.errorMessage ?? 'Gagal terhubung ke ${device.name}.', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor),
    );
  }

  IconData _signalIcon(int? rssi) {
    if (rssi == null) return Icons.bluetooth;
    if (rssi >= -60) return Icons.signal_cellular_alt;
    if (rssi >= -80) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PrinterProvider>();
    final devices = provider.bleDevices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Printer BLE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanning ? null : _scan,
            tooltip: 'Scan ulang',
          ),
        ],
      ),
      body: _scanning
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: Lottie.asset(
                      'assets/lottie/bluetooth_scan_pulse.json',
                      errorBuilder: (c, e, s) => const CircularProgressIndicator(),
                    ),
                  ),
                  const SizedBox(height: UiConstants.spacingMd),
                  const Text('Mencari printer BLE di sekitar...'),
                ],
              ),
            )
          : devices.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(UiConstants.spacingLg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
                        const SizedBox(height: UiConstants.spacingMd),
                        const Text('Tidak ada printer BLE ditemukan.', textAlign: TextAlign.center),
                        const SizedBox(height: UiConstants.spacingMd),
                        ElevatedButton.icon(
                          onPressed: _scan,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Scan Ulang'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _scan,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(UiConstants.spacingMd),
                    itemCount: devices.length,
                    itemBuilder: (context, i) {
                      final device = devices[i];
                      final isConnecting = _connectingAddress == device.address;
                      return Card(
                        margin: const EdgeInsets.only(bottom: UiConstants.spacingSm),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                            child: const Icon(Icons.print, color: AppTheme.primaryColor),
                          ),
                          title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(device.address),
                          trailing: isConnecting
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (device.rssi != null) ...[
                                      Icon(_signalIcon(device.rssi), size: 18, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text('${device.rssi}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ],
                                ),
                          onTap: isConnecting ? null : () => _connect(device),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
