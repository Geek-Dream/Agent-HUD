import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'device_store.dart';
import 'pages/devices_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DeviceStore();
  await store.load();
  runApp(
      ChangeNotifierProvider.value(value: store, child: const AgentHudApp()));
}

class AgentHudApp extends StatelessWidget {
  const AgentHudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgentHUD',
      debugShowCheckedModeBanner: false,
      theme: buildHudTheme(),
      home: const DevicesPage(),
    );
  }
}
