import 'package:flutter/material.dart';

import 'ui/main_view.dart';

class IslaApp extends StatelessWidget {
  const IslaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ISLA',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF4FC3F7),
        useMaterial3: true,
      ),
      home: const MainView(),
    );
  }
}
