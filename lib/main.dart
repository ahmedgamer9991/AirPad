import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/connection_screen.dart';

void main() {
  // Ensure Flutter engine is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Support automatic rotation between portrait and landscape modes
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    runApp(const AirPadApp());
  });
}

class AirPadApp extends StatelessWidget {
  const AirPadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AirPad',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.cyan,
        scaffoldBackgroundColor: const Color(0xFF020617),
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyan,
          secondary: Colors.deepPurpleAccent,
          surface: Color(0xFF0F172A),
          background: Color(0xFF020617),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const ConnectionScreen(),
    );
  }
}
