import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'features/watchlist/providers/watchlist_provider.dart';
import 'features/chart/providers/chart_provider.dart';
import 'features/tracker/providers/tracker_provider.dart';

import 'features/watchlist/presentation/watchlist_screen.dart';
import 'features/chart/presentation/chart_screen.dart';
import 'features/tracker/presentation/tracker_screen.dart';

void main() {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for Desktop (Windows)
  if (!kIsWeb && Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WatchlistProvider()),
        ChangeNotifierProvider(create: (_) => ChartProvider()),
        ChangeNotifierProvider(create: (_) => TrackerProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptoView',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0F14),
        primaryColor: const Color(0xFF00E6B8),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E6B8),
          secondary: Color(0xFFF0B90B),
          background: Color(0xFF0C0F14),
          surface: Color(0xFF171A22),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontFamily: 'Outfit'),
          bodyMedium: TextStyle(color: Color(0xFF90A4AE), fontFamily: 'Outfit'),
        ),
      ),
      home: const MainContainer(),
    );
  }
}

class MainContainer extends StatefulWidget {
  const MainContainer({Key? key}) : super(key: key);

  @override
  _MainContainerState createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      WatchlistScreen(onTabChange: _onTabChange),
      const ChartScreen(),
      const TrackerScreen(),
    ];
  }

  void _onTabChange(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isWide = width > 950;

    if (isWide) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0F14),
        body: Row(
          children: [
            // Left Sidebar: Watchlist
            SizedBox(
              width: 320,
              child: WatchlistScreen(onTabChange: (_) {}),
            ),
            // Vertical Separator
            Container(
              width: 1,
              color: const Color(0xFF1E2738),
            ),
            // Middle: Chart Screen
            const Expanded(
              flex: 5,
              child: ChartScreen(),
            ),
            // Vertical Separator
            Container(
              width: 1,
              color: const Color(0xFF1E2738),
            ),
            // Right: Tracker/Operations
            const Expanded(
              flex: 4,
              child: TrackerScreen(),
            ),
          ],
        ),
      );
    }

    // Narrow layout (Mobile)
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFF1E2738), width: 1),
          ),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF12161F),
          currentIndex: _currentIndex,
          selectedItemColor: const Color(0xFF00E6B8),
          unselectedItemColor: const Color(0xFF90A4AE),
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.star_border),
              activeIcon: Icon(Icons.star, color: Color(0xFF00E6B8)),
              label: 'Seguimiento',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.show_chart),
              activeIcon: Icon(Icons.show_chart, color: Color(0xFF00E6B8)),
              label: 'Gráfico',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet, color: Color(0xFF00E6B8)),
              label: 'Diario',
            ),
          ],
        ),
      ),
    );
  }
}
