import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.inicializarHost();
  runApp(const CriptoBotApp());
}

class CriptoBotApp extends StatelessWidget {
  const CriptoBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CriptoBot Institucional',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.temaOscuro,
      home: const DashboardScreen(),
    );
  }
}
