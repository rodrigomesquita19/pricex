import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/home_screen.dart';

/// Controle global do modo kiosk para evitar loops
class KioskController {
  static bool _kioskAtivo = false;
  static bool _modoImersivoPausado = false;
  static DateTime? _ultimaTentativa;
  static const _cooldownMs = 3000; // Espera 3 segundos entre tentativas

  static bool get kioskAtivo => _kioskAtivo;
  static bool get modoImersivoPausado => _modoImersivoPausado;

  /// Pausa o modo imersivo temporariamente (para mecanismo de escape)
  static void pausarModoImersivo() {
    _modoImersivoPausado = true;
    debugPrint('[Kiosk] Modo imersivo PAUSADO pelo usuário');
  }

  /// Resume o modo imersivo
  static void resumirModoImersivo() {
    _modoImersivoPausado = false;
    debugPrint('[Kiosk] Modo imersivo RETOMADO');
  }

  /// Verifica se pode tentar aplicar kiosk (cooldown)
  static bool _podeTentar() {
    if (_ultimaTentativa == null) return true;
    final agora = DateTime.now();
    final diff = agora.difference(_ultimaTentativa!).inMilliseconds;
    return diff > _cooldownMs;
  }

  static void _marcarTentativa() {
    _ultimaTentativa = DateTime.now();
  }

  /// Aplica modo imersivo se não estiver pausado
  static void aplicarModoImersivo() {
    if (_modoImersivoPausado) {
      debugPrint('[Kiosk] Modo imersivo ignorado (pausado)');
      return;
    }
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
  }

  /// Inicia o modo kiosk com proteção contra loops
  static Future<void> iniciar() async {
    if (!_podeTentar()) {
      debugPrint('[Kiosk] Ignorando tentativa (cooldown ativo)');
      return;
    }
    _marcarTentativa();

    try {
      // Verifica status atual antes de tentar
      final statusAtual = await getKioskMode();
      if (statusAtual == KioskMode.enabled) {
        _kioskAtivo = true;
        debugPrint('[Kiosk] Já está ativo, ignorando');
        return;
      }

      await startKioskMode();
      _kioskAtivo = true;
      debugPrint('[Kiosk] Modo kiosk iniciado');
    } catch (e) {
      debugPrint('[Kiosk] Erro ao iniciar modo kiosk: $e');
    }
  }

  /// Para o modo kiosk
  static Future<void> parar() async {
    try {
      await stopKioskMode();
      _kioskAtivo = false;
      debugPrint('[Kiosk] Modo kiosk parado');
    } catch (e) {
      debugPrint('[Kiosk] Erro ao parar modo kiosk: $e');
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Forcar apenas modo retrato
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Manter tela sempre acesa
  WakelockPlus.enable();

  // Configurar modo imersivo inicial
  KioskController.aplicarModoImersivo();

  runApp(const PriceXApp());
}

/// Inicia o modo kiosk (Lock Task Mode) - mantido para compatibilidade
Future<void> iniciarModoKiosk() async {
  await KioskController.iniciar();
}

/// Para o modo kiosk - mantido para compatibilidade
Future<void> pararModoKiosk() async {
  await KioskController.parar();
}

/// Verifica o status do modo kiosk
Future<KioskMode> verificarModoKiosk() async {
  return await getKioskMode();
}

/// Widget que detecta múltiplos toques rápidos para desbloquear o modo kiosk
/// Coloque uma área invisível no canto superior direito da tela
class KioskEscapeZone extends StatefulWidget {
  final Widget child;
  final int toquesNecessarios;
  final Duration tempoLimite;
  final VoidCallback onEscape;

  const KioskEscapeZone({
    super.key,
    required this.child,
    this.toquesNecessarios = 5,
    this.tempoLimite = const Duration(seconds: 3),
    required this.onEscape,
  });

  @override
  State<KioskEscapeZone> createState() => _KioskEscapeZoneState();
}

class _KioskEscapeZoneState extends State<KioskEscapeZone> {
  int _contadorToques = 0;
  DateTime? _primeiroToque;

  void _onTap() {
    final agora = DateTime.now();

    // Reset se passou muito tempo desde o primeiro toque
    if (_primeiroToque != null && agora.difference(_primeiroToque!) > widget.tempoLimite) {
      _contadorToques = 0;
      _primeiroToque = null;
    }

    // Primeiro toque da sequência
    if (_contadorToques == 0) {
      _primeiroToque = agora;
    }

    _contadorToques++;
    debugPrint('[KioskEscape] Toque ${_contadorToques}/${widget.toquesNecessarios}');

    // Atingiu o número necessário
    if (_contadorToques >= widget.toquesNecessarios) {
      _contadorToques = 0;
      _primeiroToque = null;
      widget.onEscape();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usar Listener para não interferir com GestureDetectors dos widgets filhos
    // Listener é passivo e não compete por gestos
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (event) {
        // Verifica se o toque foi no canto superior esquerdo (área 80x80)
        final pos = event.localPosition;
        if (pos.dx < 80 && pos.dy < 80) {
          _onTap();
        }
      },
      child: widget.child,
    );
  }
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

    // Iniciar modo kiosk ao abrir o app (com delay para estabilidade)
    Future.delayed(const Duration(milliseconds: 500), () {
      iniciarModoKiosk();
    });

    // Configurar callback para re-esconder a UI quando ela aparecer
    // Usando delay maior e verificando se não está pausado
    SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
      if (systemOverlaysAreVisible && !KioskController.modoImersivoPausado) {
        await Future.delayed(const Duration(seconds: 2));
        KioskController.aplicarModoImersivo();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !KioskController.modoImersivoPausado) {
      KioskController.aplicarModoImersivo();
      // Não re-inicia o kiosk automaticamente no resume para evitar loops
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
