import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
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
      ],
      child: MaterialApp(
        title: 'PeriPage A9',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        home: const HomeScreen(),
      ),
    );
  }
}
