import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/price_scanner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Forcar apenas modo retrato
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configurar para tela cheia
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  runApp(const PriceXApp());
}

class PriceXApp extends StatelessWidget {
  const PriceXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PriceX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const PriceScannerScreen(),
    );
  }
}
