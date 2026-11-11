import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'device_store.dart';
import 'pages/devices_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DeviceStore();
  await store.load();
  runApp(ChangeNotifierProvider.value(value: store, child: const AgentHudApp()));
}

class AgentHudApp extends StatelessWidget {
  const AgentHudApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF60A5FA),
      brightness: Brightness.dark,
      surface: const Color(0xFF101722),
    );
    return MaterialApp(
      title: 'AgentHUD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0B1120),
        cardTheme: CardThemeData(
          color: const Color(0xFF17202D),
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF2B3748)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF17202D),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const DevicesPage(),
    );
  }
}
