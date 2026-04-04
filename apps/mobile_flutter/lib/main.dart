import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/home_page.dart';

void main() {
  // Ensure bindings before runApp, enable Riverpod
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RainApp()));
}

class RainApp extends StatelessWidget {
  const RainApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rain Flutter',
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
