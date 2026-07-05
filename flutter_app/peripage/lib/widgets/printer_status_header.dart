import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Header animasi status koneksi printer -- MENGGANTI judul statis
/// "PeriPage A9" dengan indikator visual realtime (pulsing ring biru kalau
/// connected, abu-abu diam kalau tidak). Nama app sendiri sudah dipindah
/// jadi "PyPeriPage" di title bar OS, jadi header ini fokus ke STATUS,
/// bukan branding statis.
class PrinterStatusHeader extends StatelessWidget {
  final bool isConnected;
  final String? deviceName;
  final VoidCallback? onTap;

  const PrinterStatusHeader({
    super.key,
    required this.isConnected,
    this.deviceName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Lottie.asset(
                isConnected
                    ? 'assets/lottie/printer_pulse_connected.json'
                    : 'assets/lottie/printer_pulse_disconnected.json',
                repeat: true,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.print,
                  color: isConnected ? Colors.white : Colors.white54,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isConnected ? 'Terhubung' : 'Tidak Terhubung',
                  style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 15),
                ),
                if (isConnected && deviceName != null)
                  Text(
                    deviceName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.75),
                        ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
