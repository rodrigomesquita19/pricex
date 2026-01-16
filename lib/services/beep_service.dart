import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Servico para tocar sons de feedback
class BeepService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _initialized = false;

  // Som de beep em formato WAV (base64) - tom de 1000Hz por 200ms
  static const String _beepBase64 = '''
UklGRmQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YUAAAAD//wAA//8AAP//AAD/
/wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//AAD//wAA//8AAP//
AAD//wAA
''';

  /// Inicializa o servico de som
  static Future<void> _initialize() async {
    if (_initialized) return;
    try {
      await _player.setVolume(0.8);
      await _player.setReleaseMode(ReleaseMode.stop);
      _initialized = true;
    } catch (e) {
      debugPrint('[BeepService] Erro ao inicializar: $e');
    }
  }

  /// Toca som de sucesso (beep)
  static Future<void> playSuccess() async {
    try {
      await _initialize();

      // Tentar carregar do asset primeiro
      try {
        await _player.play(AssetSource('sounds/beep.mp3'), volume: 0.8);
        return;
      } catch (_) {
        // Arquivo nao existe, usar beep embutido
      }

      // Usar beep embutido em base64
      try {
        final bytes = base64Decode(_beepBase64.replaceAll('\n', ''));
        await _player.play(
          BytesSource(Uint8List.fromList(bytes)),
          volume: 0.8,
        );
        return;
      } catch (_) {
        // Fallback para URL
      }

      // Fallback para URL
      await _player.play(
        UrlSource('https://cdn.freesound.org/previews/254/254316_4062622-lq.mp3'),
        volume: 0.6,
      );
    } catch (e) {
      debugPrint('[BeepService] Erro ao tocar som: $e');
    }
  }

  /// Toca som de erro
  static Future<void> playError() async {
    try {
      await _initialize();
      await _player.play(AssetSource('sounds/error.mp3'), volume: 0.8);
    } catch (e) {
      debugPrint('[BeepService] Erro ao tocar som de erro: $e');
    }
  }

  /// Libera recursos
  static Future<void> dispose() async {
    await _player.dispose();
    _initialized = false;
  }
}
