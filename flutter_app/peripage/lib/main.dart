import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/theme_controller.dart';
import 'providers/printer_provider.dart';
import 'screens/home/home_screen.dart';
import 'services/desktop_backend_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Start desktop backend otomatis untuk platform desktop
  if (DesktopBackendService().isDesktop) {
    await DesktopBackendService().startBackend();
  }
  
  runApp(const PeriPageApp());
}

class PeriPageApp extends StatelessWidget {
  const PeriPageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PrinterProvider()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeController, _) {
          return MaterialApp(
            // Nama aplikasi disamakan dengan nama package/repo "pyperipage"
            // (sebelumnya "PeriPage A9" -- itu sekarang cuma nama produk yang
            // ditampilkan di header via animasi printer, bukan judul app).
            title: 'PyPeriPage',
            debugShowCheckedModeBanner: false,
            theme: themeController.themeData,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
