import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/database_config.dart';
import '../models/grupo_exibicao.dart';

class ConfigService {
  static const String _configKey = 'database_config';
  static const String _tabelaDescontoKey = 'tabela_desconto_id';
  static const String _gruposExibicaoKey = 'grupos_exibicao';
  static const String _carrosselAtivoKey = 'carrossel_ativo';
  static const String _tempoCarrosselKey = 'tempo_carrossel_segundos';

  /// Salva a configuracao do banco de dados
  static Future<void> saveConfig(DatabaseConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(config.toJson());
    await prefs.setString(_configKey, jsonString);
  }

  /// Obtem a configuracao do banco de dados
  static Future<DatabaseConfig?> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_configKey);

    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }

    try {
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return DatabaseConfig.fromJson(jsonMap);
    } catch (e) {
      return null;
    }
  }

  /// Verifica se existe configuracao salva
  static Future<bool> hasConfig() async {
    final config = await getConfig();
    return config != null && config.isConfigured;
  }

  /// Limpa a configuracao salva
  static Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configKey);
  }

  /// Salva o ID da tabela de desconto padrao
  static Future<void> saveTabelaDescontoId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tabelaDescontoKey, id);
  }

  /// Obtem o ID da tabela de desconto padrao (1 como padrao)
  static Future<int> getTabelaDescontoId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_tabelaDescontoKey) ?? 1;
  }

  // ===== GRUPOS DE EXIBICAO (CARROSSEL) =====

  /// Salva os grupos de exibicao
  static Future<void> saveGruposExibicao(List<GrupoExibicao> grupos) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = grupos.map((g) => g.toMap()).toList();
    await prefs.setString(_gruposExibicaoKey, jsonEncode(jsonList));
  }

  /// Obtem os grupos de exibicao
  static Future<List<GrupoExibicao>> getGruposExibicao() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_gruposExibicaoKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((item) => GrupoExibicao.fromMap(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Adiciona um grupo de exibicao
  static Future<void> addGrupoExibicao(GrupoExibicao grupo) async {
    final grupos = await getGruposExibicao();
    grupos.add(grupo);
    await saveGruposExibicao(grupos);
  }

  /// Atualiza um grupo de exibicao
  static Future<void> updateGrupoExibicao(GrupoExibicao grupo) async {
    final grupos = await getGruposExibicao();
    final index = grupos.indexWhere((g) => g.id == grupo.id);
    if (index != -1) {
      grupos[index] = grupo;
      await saveGruposExibicao(grupos);
    }
  }

  /// Remove um grupo de exibicao
  static Future<void> removeGrupoExibicao(String id) async {
    final grupos = await getGruposExibicao();
    grupos.removeWhere((g) => g.id == id);
    await saveGruposExibicao(grupos);
  }

  /// Salva se o carrossel esta ativo
  static Future<void> saveCarrosselAtivo(bool ativo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_carrosselAtivoKey, ativo);
  }

  /// Verifica se o carrossel esta ativo
  static Future<bool> isCarrosselAtivo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_carrosselAtivoKey) ?? false;
  }

  /// Salva o tempo de exibicao do carrossel (em segundos)
  static Future<void> saveTempoCarrossel(int segundos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tempoCarrosselKey, segundos);
  }

  /// Obtem o tempo de exibicao do carrossel (padrao: 10 segundos)
  static Future<int> getTempoCarrossel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_tempoCarrosselKey) ?? 10;
  }
}
