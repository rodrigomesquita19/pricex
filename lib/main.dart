import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Forcar apenas modo retrato
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Configurar modo imersivo inicial
  _aplicarModoImersivo();

  runApp(const PriceXApp());
}

/// Aplica o modo imersivo (esconde barras do sistema)
void _aplicarModoImersivo() {
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );
}

/// Inicia o modo kiosk (Lock Task Mode)
Future<void> iniciarModoKiosk() async {
  try {
    await startKioskMode();
    debugPrint('[Kiosk] Modo kiosk iniciado');
  } catch (e) {
    debugPrint('[Kiosk] Erro ao iniciar modo kiosk: $e');
  }
}

/// Para o modo kiosk
Future<void> pararModoKiosk() async {
  try {
    await stopKioskMode();
    debugPrint('[Kiosk] Modo kiosk parado');
  } catch (e) {
    debugPrint('[Kiosk] Erro ao parar modo kiosk: $e');
  }
}

/// Verifica o status do modo kiosk
Future<KioskMode> verificarModoKiosk() async {
  return await getKioskMode();
}

class PriceXApp extends StatefulWidget {
  const PriceXApp({super.key});

  @override
  State<PriceXApp> createState() => _PriceXAppState();
}

class _PriceXAppState extends State<PriceXApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Iniciar modo kiosk ao abrir o app
    _inicializarKiosk();

    // Configurar callback para re-esconder a UI quando ela aparecer
    SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
      if (systemOverlaysAreVisible) {
        await Future.delayed(const Duration(seconds: 1));
        _aplicarModoImersivo();
      }
    });
  }

  Future<void> _inicializarKiosk() async {
    await iniciarModoKiosk();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _aplicarModoImersivo();
      iniciarModoKiosk();
    }
  }

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
      home: const HomeScreen(),
    );
  }
}
