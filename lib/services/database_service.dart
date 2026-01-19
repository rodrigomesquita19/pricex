import 'package:flutter/foundation.dart';
import 'package:mysql1/mysql1.dart';
import '../models/database_config.dart';
import 'config_service.dart';

/// Tipos de erro de conexao
enum ConnectionErrorType {
  serverNotFound,
  databaseNotFound,
  authFailed,
  unknown,
}

/// Tipos de origem de preco
enum OrigemPreco {
  normal,
  promocao,
  promocaoFilial,
  descAvista,
  descRegra,
  tabloide,
  descontoQuantidade,
  combo,
  loteDesconto,
}

/// Regra de desconto por quantidade
class RegraDescontoQtde {
  final int quantidade;
  final double desconto;

  RegraDescontoQtde({required this.quantidade, required this.desconto});

  Map<String, dynamic> toMap() => {'quantidade': quantidade, 'desconto': desconto};
}

/// Produto de um combo/kit
class ComboProduto {
  final int produtoId;
  final String descricao;
  final String? barras;
  final int qtdMinima;
  final double precoOriginal;
  final double? precoKit;
  final double descontoPerc;

  ComboProduto({
    required this.produtoId,
    required this.descricao,
    this.barras,
    required this.qtdMinima,
    required this.precoOriginal,
    this.precoKit,
    required this.descontoPerc,
  });

  /// Calcula economia por unidade
  double get economiaPorUnidade => precoKit != null ? (precoOriginal - precoKit!) : 0;

  /// Calcula economia total (qtdMinima * economia por unidade)
  double get economiaTotal => economiaPorUnidade * qtdMinima;

  Map<String, dynamic> toMap() => {
    'produtoId': produtoId,
    'descricao': descricao,
    'barras': barras,
    'qtdMinima': qtdMinima,
    'precoOriginal': precoOriginal,
    'precoKit': precoKit,
    'descontoPerc': descontoPerc,
    'economiaPorUnidade': economiaPorUnidade,
    'economiaTotal': economiaTotal,
  };
}

/// Grupo de precos de um combo/kit
class ComboGrupoPreco {
  final int grupoPrecoId;
  final String descricao;
  final int qtdMinima;
  final double? precoKit;
  final int qtdProdutosNoGrupo;

  ComboGrupoPreco({
    required this.grupoPrecoId,
    required this.descricao,
    required this.qtdMinima,
    this.precoKit,
    required this.qtdProdutosNoGrupo,
  });

  Map<String, dynamic> toMap() => {
    'grupoPrecoId': grupoPrecoId,
    'descricao': descricao,
    'qtdMinima': qtdMinima,
    'precoKit': precoKit,
    'qtdProdutosNoGrupo': qtdProdutosNoGrupo,
  };
}

/// Informacoes de combo/kit disponivel
class ComboDisponivel {
  final int kitPromoId;
  final String descricao;
  final int qtdMinima;
  final double descontoPerc;
  final double? precoFixo;
  final List<ComboProduto> produtos;
  final List<ComboGrupoPreco> gruposPreco;

  ComboDisponivel({
    required this.kitPromoId,
    required this.descricao,
    required this.qtdMinima,
    required this.descontoPerc,
    this.precoFixo,
    this.produtos = const [],
    this.gruposPreco = const [],
  });

  /// Calcula economia total do combo (soma das economias de todos os produtos)
  double get economiaTotal {
    double economia = 0;
    for (final prod in produtos) {
      economia += prod.economiaTotal;
    }
    return economia;
  }

  /// Verifica se tem grupos de preco (outros produtos elegiveis)
  bool get temGruposPreco => gruposPreco.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'kitPromoId': kitPromoId,
    'descricao': descricao,
    'qtdMinima': qtdMinima,
    'descontoPerc': descontoPerc,
    'precoFixo': precoFixo,
    'produtos': produtos.map((p) => p.toMap()).toList(),
    'gruposPreco': gruposPreco.map((g) => g.toMap()).toList(),
    'economiaTotal': economiaTotal,
    'temGruposPreco': temGruposPreco,
  };
}

/// Informacoes de lote com desconto
class LoteDesconto {
  final int loteNovoId;
  final String lote;
  final DateTime? validade;
  final double percDesconto;
  final int estoque;

  LoteDesconto({
    required this.loteNovoId,
    required this.lote,
    this.validade,
    required this.percDesconto,
    required this.estoque,
  });

  int get diasAteVencimento => validade?.difference(DateTime.now()).inDays ?? 999999;
  bool get estaVencido => validade?.isBefore(DateTime.now()) ?? false;

  Map<String, dynamic> toMap() => {
    'loteNovoId': loteNovoId,
    'lote': lote,
    'validade': validade?.toIso8601String(),
    'percDesconto': percDesconto,
    'estoque': estoque,
    'diasAteVencimento': diasAteVencimento,
  };
}

/// Resultado do teste de conexao
class ConnectionTestResult {
  final bool success;
  final ConnectionErrorType? errorType;
  final String message;

  ConnectionTestResult({
    required this.success,
    required this.errorType,
    required this.message,
  });
}

/// Servico de conexao com o banco de dados MariaDB
class DatabaseService {
  static MySqlConnection? _connection;
  static int? _filialId;
  static int? _grupoPrecoId;

  /// Obtem conexao com o banco de dados
  static Future<MySqlConnection?> getConnection() async {
    try {
      // Se ja tem conexao ativa, retorna ela
      if (_connection != null) {
        try {
          await _connection!.query('SELECT 1');
          return _connection;
        } catch (e) {
          debugPrint('[DatabaseService] Conexao perdida, reconectando...');
          _connection = null;
        }
      }

      // Busca configuracao salva
      final config = await ConfigService.getConfig();
      if (config == null || !config.isConfigured) {
        debugPrint('[DatabaseService] Configuracao nao encontrada');
        return null;
      }

      // Conecta ao banco
      final settings = ConnectionSettings(
        host: config.host,
        port: config.port,
        user: config.username,
        password: config.password,
        db: config.database,
        timeout: const Duration(seconds: 30),
      );

      _connection = await MySqlConnection.connect(settings);
      debugPrint('[DatabaseService] Conectado a ${config.host}:${config.port}/${config.database}');

      // Carrega dados da filial
      await _carregarDadosFilial();

      return _connection;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao conectar: $e');
      return null;
    }
  }

  /// Carrega dados da filial (filial_id e grupo_preco_id)
  static Future<void> _carregarDadosFilial() async {
    if (_connection == null) return;

    try {
      // Busca filial_id
      final filialResults = await _connection!.query(
        'SELECT filial_id FROM identificacao_servidor LIMIT 1',
      );

      if (filialResults.isNotEmpty) {
        _filialId = (filialResults.first['filial_id'] as num?)?.toInt();
        debugPrint('[DatabaseService] Filial ID: $_filialId');
      }

      // Busca grupo_preco_id da filial
      if (_filialId != null) {
        final grupoPrecoResults = await _connection!.query('''
          SELECT grupo_preco_id
          FROM grupo_preco_filial
          WHERE filial_id = ?
            AND apagado = 'N'
          LIMIT 1
        ''', [_filialId]);

        if (grupoPrecoResults.isNotEmpty) {
          _grupoPrecoId = (grupoPrecoResults.first['grupo_preco_id'] as num?)?.toInt();
          debugPrint('[DatabaseService] Grupo Preco ID: $_grupoPrecoId');
        }
      }
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao carregar dados da filial: $e');
    }
  }

  /// Retorna o ID da filial
  static int? get filialId => _filialId;

  /// Retorna o ID do grupo de preco
  static int? get grupoPrecoId => _grupoPrecoId;

  /// Busca o CNPJ da filial (coluna cgc)
  static Future<String?> getCnpjFilial() async {
    final conn = await _getConnection();
    if (conn == null || _filialId == null) return null;

    try {
      final results = await conn.query('''
        SELECT cgc FROM filial WHERE filial_id = ? LIMIT 1
      ''', [_filialId]);

      if (results.isNotEmpty) {
        final cnpj = results.first['cgc']?.toString() ?? '';
        // Remover formatacao, deixar so numeros
        return cnpj.replaceAll(RegExp(r'[^0-9]'), '');
      }
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar CNPJ: $e');
    }
    return null;
  }

  /// Fecha a conexao atual
  static Future<void> closeConnection() async {
    if (_connection != null) {
      try {
        await _connection!.close();
      } catch (e) {
        debugPrint('[DatabaseService] Erro ao fechar conexao: $e');
      }
      _connection = null;
      _filialId = null;
      _grupoPrecoId = null;
    }
  }

  /// Testa a conexao e retorna resultado detalhado
  static Future<ConnectionTestResult> testConnectionDetailed(DatabaseConfig config) async {
    MySqlConnection? conn;
    try {
      debugPrint('[DatabaseService] Testando conexao com ${config.host}:${config.port}/${config.database}...');

      // Primeiro tenta conectar sem banco especifico para verificar se servidor existe
      try {
        final settingsNoDb = ConnectionSettings(
          host: config.host,
          port: config.port,
          user: config.username,
          password: config.password,
          timeout: const Duration(seconds: 15),
        );

        conn = await MySqlConnection.connect(settingsNoDb);
        await conn.close();
        conn = null;
      } catch (e) {
        final errorStr = e.toString().toLowerCase();

        if (errorStr.contains('timeout') ||
            errorStr.contains('socket') ||
            errorStr.contains('connection refused') ||
            errorStr.contains('no route') ||
            errorStr.contains('network is unreachable')) {
          debugPrint('[DatabaseService] MariaDB nao encontrado no IP');
          return ConnectionTestResult(
            success: false,
            errorType: ConnectionErrorType.serverNotFound,
            message: 'Nao foi possivel localizar o MariaDB em ${config.host}:${config.port}',
          );
        }

        if (errorStr.contains('access denied')) {
          debugPrint('[DatabaseService] Servidor encontrado mas credenciais invalidas');
          return ConnectionTestResult(
            success: false,
            errorType: ConnectionErrorType.authFailed,
            message: 'Usuario ou senha incorretos',
          );
        }
      }

      // Agora tenta conectar com o banco especifico
      final settings = ConnectionSettings(
        host: config.host,
        port: config.port,
        user: config.username,
        password: config.password,
        db: config.database,
        timeout: const Duration(seconds: 15),
      );

      conn = await MySqlConnection.connect(settings);
      await conn.query('SELECT 1');

      debugPrint('[DatabaseService] Conexao testada com sucesso!');
      return ConnectionTestResult(
        success: true,
        errorType: null,
        message: 'Conexao estabelecida com sucesso!',
      );
    } catch (e) {
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('unknown database') ||
          errorStr.contains('does not exist') ||
          errorStr.contains("doesn't exist")) {
        return ConnectionTestResult(
          success: false,
          errorType: ConnectionErrorType.databaseNotFound,
          message: 'O banco de dados "${config.database}" nao existe no servidor',
        );
      }

      if (errorStr.contains('access denied')) {
        return ConnectionTestResult(
          success: false,
          errorType: ConnectionErrorType.authFailed,
          message: 'Usuario ou senha incorretos',
        );
      }

      if (errorStr.contains('timeout') ||
          errorStr.contains('socket') ||
          errorStr.contains('connection refused')) {
        return ConnectionTestResult(
          success: false,
          errorType: ConnectionErrorType.serverNotFound,
          message: 'Nao foi possivel localizar o MariaDB em ${config.host}:${config.port}',
        );
      }

      return ConnectionTestResult(
        success: false,
        errorType: ConnectionErrorType.unknown,
        message: 'Erro ao conectar: ${e.toString().split('\n').first}',
      );
    } finally {
      if (conn != null) {
        try {
          await conn.close();
        } catch (_) {}
      }
    }
  }

  /// Busca produto por codigo de barras e retorna precos
  static Future<Map<String, dynamic>> buscarProdutoPorCodigoBarras(
    String codigoBarras, {
    int? tabelaDescontoId,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        return {'erro': 'Sem conexao com o banco de dados'};
      }

      if (_filialId == null || _grupoPrecoId == null) {
        return {'erro': 'Dados da filial nao configurados'};
      }

      // Primeiro busca na tabela produto pela coluna barras
      var results = await conn.query('''
        SELECT
          p.Produto_id,
          p.descricao,
          p.barras,
          p.grupo_id,
          p.inativo,
          f.descricao as fabricante_nome,
          COALESCE(em.estoque, 0) as estoque,
          COALESCE(gpp.preco_vnd, 0) as preco_vnd
        FROM produto p
        LEFT JOIN fabricantes f ON f.fabricantes_id = p.fabricantes_id AND f.apagado = 'N'
        LEFT JOIN estoque_minimo em ON em.produto_id = p.Produto_id AND em.filial_id = ?
        LEFT JOIN grupo_preco_produto gpp ON gpp.produto_id = p.Produto_id AND gpp.grupo_preco_id = ?
        WHERE p.barras = ?
          AND p.apagado = 'N'
        LIMIT 1
      ''', [_filialId, _grupoPrecoId, codigoBarras]);

      // Se nao encontrou, busca na tabela barras
      if (results.isEmpty) {
        results = await conn.query('''
          SELECT
            p.Produto_id,
            p.descricao,
            b.barras,
            p.grupo_id,
            p.inativo,
            f.descricao as fabricante_nome,
            COALESCE(em.estoque, 0) as estoque,
            COALESCE(gpp.preco_vnd, 0) as preco_vnd
          FROM barras b
          INNER JOIN produto p ON p.Produto_id = b.produto_id AND p.apagado = 'N'
          LEFT JOIN fabricantes f ON f.fabricantes_id = p.fabricantes_id AND f.apagado = 'N'
          LEFT JOIN estoque_minimo em ON em.produto_id = p.Produto_id AND em.filial_id = ?
          LEFT JOIN grupo_preco_produto gpp ON gpp.produto_id = p.Produto_id AND gpp.grupo_preco_id = ?
          WHERE b.barras = ?
            AND b.apagado = 'N'
          LIMIT 1
        ''', [_filialId, _grupoPrecoId, codigoBarras]);
      }

      if (results.isEmpty) {
        return {'erro': 'Produto nao encontrado', 'codigo': codigoBarras};
      }

      final row = results.first;

      // Verifica se o produto esta inativo
      final inativo = row['inativo']?.toString() ?? 'N';
      if (inativo == 'S') {
        return {
          'erro': 'Produto inativo',
          'mensagem': 'Este cadastro esta inativo atualmente.',
          'codigo': codigoBarras,
          'descricao': row['descricao']?.toString() ?? '',
        };
      }

      final produtoId = (row['Produto_id'] as num?)?.toInt() ?? 0;
      final grupoId = (row['grupo_id'] as num?)?.toInt() ?? 0;
      final precoVnd = (row['preco_vnd'] as num?)?.toDouble() ?? 0;

      // Calcular preco praticado
      double precoPraticado = precoVnd;
      double precoCheio = precoVnd;
      String origemPreco = 'NORMAL';
      bool isPromocional = false;
      DateTime? dataFimPromocao;

      if (tabelaDescontoId != null && tabelaDescontoId > 0) {
        final precosCalculados = await _calcularPrecoPraticado(
          produtoId: produtoId,
          grupoId: grupoId,
          tabelaDescontoId: tabelaDescontoId,
        );

        if (precosCalculados != null) {
          precoCheio = precosCalculados['preco_cheio'] as double;
          precoPraticado = precosCalculados['preco_praticado'] as double;
          origemPreco = precosCalculados['origem_preco'] as String? ?? 'NORMAL';
          isPromocional = precoPraticado < precoCheio;

          // Data fim da promocao
          final dataFimStr = precosCalculados['data_fim_promocao'] as String?;
          if (dataFimStr != null) {
            dataFimPromocao = DateTime.tryParse(dataFimStr);
          }
        }
      }

      // Buscar informacoes adicionais de desconto
      final regrasDescQtde = await buscarDescontoQuantidade(produtoId);
      final combos = await buscarCombosDisponiveis(produtoId, tabelaDescontoId: tabelaDescontoId);
      final lotesDesconto = await buscarLotesComDesconto(produtoId, omitirProximoVencimento: true);

      // Gerar sugestao de desconto quantidade
      String? sugestaoDescQtde;
      bool temDescontoQuantidade = regrasDescQtde.isNotEmpty;
      if (temDescontoQuantidade) {
        sugestaoDescQtde = gerarSugestaoDescontoQtde(
          regras: regrasDescQtde,
          precoCheio: precoCheio,
        );
      }

      // Verificar se tem combo disponivel
      bool temCombo = combos.isNotEmpty;
      String? descricaoCombo;
      if (temCombo) {
        descricaoCombo = combos.first.descricao;
      }

      // Verificar se tem lote com desconto
      bool temLoteDesconto = lotesDesconto.isNotEmpty;
      double? maiorDescontoLote;
      if (temLoteDesconto) {
        maiorDescontoLote = lotesDesconto.first.percDesconto;
      }

      // Calcular dias restantes da promocao (comparando apenas datas, sem horas)
      int? diasRestantesPromocao;
      if (dataFimPromocao != null) {
        final hoje = DateTime.now();
        final hojeApenasDia = DateTime(hoje.year, hoje.month, hoje.day);
        final fimApenasDia = DateTime(dataFimPromocao.year, dataFimPromocao.month, dataFimPromocao.day);
        diasRestantesPromocao = fimApenasDia.difference(hojeApenasDia).inDays;
      }

      return {
        'sucesso': true,
        'produtoId': produtoId,
        'descricao': row['descricao']?.toString() ?? '',
        'barras': row['barras']?.toString() ?? '',
        'grupoId': grupoId,
        'fabricanteNome': row['fabricante_nome']?.toString() ?? '',
        'estoque': (row['estoque'] as num?)?.toInt() ?? 0,
        'precoPraticado': precoPraticado,
        'precoCheio': precoCheio,
        'origemPreco': origemPreco,
        'isPromocional': isPromocional,
        // Promocao
        'dataFimPromocao': dataFimPromocao?.toIso8601String(),
        'diasRestantesPromocao': diasRestantesPromocao,
        // Desconto Quantidade
        'temDescontoQuantidade': temDescontoQuantidade,
        'regrasDescontoQtde': regrasDescQtde.map((r) => r.toMap()).toList(),
        'sugestaoDescontoQtde': sugestaoDescQtde,
        // Combos
        'temCombo': temCombo,
        'combos': combos.map((c) => c.toMap()).toList(),
        'descricaoCombo': descricaoCombo,
        // Lote Desconto
        'temLoteDesconto': temLoteDesconto,
        'lotesDesconto': lotesDesconto.map((l) => l.toMap()).toList(),
        'maiorDescontoLote': maiorDescontoLote,
      };
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar produto: $e');
      return {'erro': 'Erro ao buscar produto: $e'};
    }
  }

  /// Calcula o preco praticado para um produto
  static Future<Map<String, dynamic>?> _calcularPrecoPraticado({
    required int produtoId,
    required int grupoId,
    required int tabelaDescontoId,
  }) async {
    if (_connection == null || _filialId == null || _grupoPrecoId == null) {
      return null;
    }

    try {
      // Determinar o dia da semana para validacao de tabloide
      final diaSemana = DateTime.now().weekday;
      final colunaDia = switch (diaSemana) {
        1 => 'dia_segunda',
        2 => 'dia_terca',
        3 => 'dia_quarta',
        4 => 'dia_quinta',
        5 => 'dia_sexta',
        6 => 'dia_sabado',
        7 => 'dia_domingo',
        _ => 'dia_segunda',
      };

      // Query principal para calcular preco praticado
      final results = await _connection!.query('''
        SELECT
            p.produto_id,

            /* Pratica preco resolvida (produto > grupo > 1) */
            COALESCE(
                NULLIF(ptd_agg.pratica_preco, 0),
                NULLIF(gtd_agg.pratica_preco, 0),
                1
            ) AS pratica_preco_resolvida,

            /* Preco base pela pratica resolvida */
            CASE COALESCE(NULLIF(ptd_agg.pratica_preco,0), NULLIF(gtd_agg.pratica_preco,0), 1)
                WHEN 1  THEN COALESCE(NULLIF(gpp.preco_vnd,0), gpp.preco2, gpp.preco3, gpp.preco_cmp_un)
                WHEN 2  THEN COALESCE(NULLIF(gpp.preco2,0),    gpp.preco_vnd, gpp.preco3, gpp.preco_cmp_un)
                WHEN 3  THEN COALESCE(NULLIF(gpp.preco3,0),    gpp.preco2, gpp.preco_vnd, gpp.preco_cmp_un)
                WHEN 10 THEN COALESCE(NULLIF(gpp.preco_cmp_un,0), gpp.preco_vnd, gpp.preco2, gpp.preco3)
                ELSE         COALESCE(gpp.preco_vnd, gpp.preco2, gpp.preco3, gpp.preco_cmp_un)
            END AS preco_cheio,

            /* Preco filial */
            pfil.preco AS preco_filial_cheio,
            CASE
                WHEN pfil.preco_promo IS NOT NULL AND CURRENT_DATE <= pfil.final_promocao
                THEN pfil.preco_promo
            END AS preco_filial_promo,
            CASE
                WHEN pfil.desc_vista > 0
                THEN pfil.preco * (1 - pfil.desc_vista/100)
            END AS preco_filial_avista,

            /* Flags de permissao efetiva (produto > grupo) */
            COALESCE(ptd_agg.permite_promocao,    gtd_agg.permite_promocao,    'N') AS perm_promocao,
            COALESCE(ptd_agg.permite_desc_avista, gtd_agg.permite_desc_avista, 'N') AS perm_desc_avista,
            COALESCE(ptd_agg.permite_desc_qtde,   gtd_agg.permite_desc_qtde,   'N') AS perm_desc_qtde,
            COALESCE(ptd_agg.permite_tabloide,    gtd_agg.permite_tabloide,    'N') AS perm_tabloide,

            /* Desconto da regra (produto > grupo) */
            COALESCE(NULLIF(ptd_agg.desconto, 0), gtd_agg.desconto, 0) AS desconto_regra,

            /* Promo do cadastro */
            CASE
                WHEN gpp.valid_pro IS NOT NULL AND CURRENT_DATE <= gpp.valid_pro
                THEN gpp.preco_pro
            END AS preco_cadastro_promo,

            /* Datas de fim de promocao */
            pfil.final_promocao AS data_fim_promo_filial,
            gpp.valid_pro AS data_fim_promo_cadastro,

            /* Desc a vista do cadastro */
            gpp.desconto AS desconto_avista_cadastro,

            /* Preco Tabloide (produto ou grupo, o menor) */
            LEAST(
                COALESCE(tbl_prod.preco_tabloide, 999999999),
                COALESCE(tbl_grupo.preco_tabloide, 999999999)
            ) AS preco_tabloide_raw,

            /* Descricao do tabloide */
            COALESCE(tbl_prod.tabloide_desc, tbl_grupo.tabloide_desc) AS tabloide_desc,

            /* Data fim do tabloide */
            COALESCE(tbl_prod.tabloide_data_fim, tbl_grupo.tabloide_data_fim) AS tabloide_data_fim

        FROM produto p
        LEFT JOIN grupo_preco_produto gpp ON gpp.produto_id = p.produto_id AND gpp.grupo_preco_id = ?
        LEFT JOIN precosfilial pfil ON pfil.produto_id = p.produto_id
            AND pfil.filial_id = ? AND pfil.apagado = 'N' AND pfil.preco > 0

        /* Regras do PRODUTO agregadas */
        LEFT JOIN (
            SELECT
                ptd.produto_id,
                MAX(ptd.pratica_preco)       AS pratica_preco,
                MAX(ptd.permite_promocao)    AS permite_promocao,
                MAX(ptd.permite_desc_avista) AS permite_desc_avista,
                MAX(ptd.permite_desc_qtde)   AS permite_desc_qtde,
                MAX(ptd.permite_tabloide)    AS permite_tabloide,
                AVG(ptd.desconto)            AS desconto
            FROM prod_tabela_desconto ptd
            WHERE ptd.tabela_desconto_id = ?
              AND ptd.apagado = 'N'
              AND ptd.produto_id = ?
            GROUP BY ptd.produto_id
        ) ptd_agg ON ptd_agg.produto_id = p.produto_id

        /* Regras do GRUPO agregadas - busca TODOS os grupos da tabela_desconto */
        LEFT JOIN (
            SELECT
                gtd.grupo_id,
                MAX(gtd.pratica_preco)       AS pratica_preco,
                MAX(gtd.permite_promocao)    AS permite_promocao,
                MAX(gtd.permite_desc_avista) AS permite_desc_avista,
                MAX(gtd.permite_desc_qtde)   AS permite_desc_qtde,
                MAX(gtd.permite_tabloide)    AS permite_tabloide,
                AVG(gtd.desconto)            AS desconto
            FROM grupo_tabela_desconto gtd
            WHERE gtd.tabela_desconto_id = ?
            GROUP BY gtd.grupo_id
        ) gtd_agg ON gtd_agg.grupo_id = p.grupo_id

        /* Tabloide por PRODUTO */
        LEFT JOIN (
            SELECT
                tdp.produto_id,
                MIN(
                    CASE
                        WHEN tdp.aplicar_perc_desconto = 'S'
                          THEN gpp2.preco_vnd * (1 - tdp.perc_desconto/100)
                        WHEN tdp.aplicar_preco_venda = 'S'
                          THEN tdp.preco_venda
                        WHEN tdp.aplicar_margem_markup = 'S'
                          THEN gpp2.preco_cmp_un * (1 + tdp.margem_markup/100)
                        WHEN tdp.aplicar_marg_custo_medio = 'S'
                          THEN COALESCE(NULLIF(pmc2.pmc_atual,0), NULLIF(gpp2.precoee,0), gpp2.preco_cmp_un)
                               * (1 + tdp.marg_custo_medio/100)
                        ELSE gpp2.preco_vnd
                    END
                ) AS preco_tabloide,
                MAX(t.descricao) AS tabloide_desc,
                MIN(t.vigencia_ate) AS tabloide_data_fim
            FROM tabloide t
            JOIN tabloide_filial tf ON tf.tabloide_id = t.tabloide_id
            JOIN tabloide_produto tdp ON tdp.tabloide_id = t.tabloide_id
            LEFT JOIN grupo_preco_produto gpp2 ON gpp2.produto_id = tdp.produto_id AND gpp2.grupo_preco_id = ?
            LEFT JOIN preco_medio_custo pmc2 ON pmc2.produto_id = tdp.produto_id AND pmc2.fillogica_id = ?
            WHERE t.apagado = 'N'
              AND t.ativo = 'S'
              AND t.vigencia_ate >= CURRENT_DATE
              AND (tf.filial_id = 0 OR tf.filial_id = ?)
              AND tdp.$colunaDia = 'S'
              AND tdp.produto_id = ?
            GROUP BY tdp.produto_id
        ) tbl_prod ON tbl_prod.produto_id = p.produto_id

        /* Tabloide por GRUPO */
        LEFT JOIN (
            SELECT
                p3.produto_id,
                MIN(
                    CASE
                        WHEN tg.aplicar_perc_desconto = 'S'
                          THEN gpp3.preco_vnd * (1 - tg.perc_desconto/100)
                        WHEN tg.aplicar_margem_markup = 'S'
                          THEN gpp3.preco_cmp_un * (1 + tg.margem_markup/100)
                        WHEN tg.aplicar_marg_custo_medio = 'S'
                          THEN COALESCE(NULLIF(pmc3.pmc_atual,0), NULLIF(gpp3.precoee,0), gpp3.preco_cmp_un)
                               * (1 + tg.marg_custo_medio/100)
                        ELSE gpp3.preco_vnd
                    END
                ) AS preco_tabloide,
                MAX(t.descricao) AS tabloide_desc,
                MIN(t.vigencia_ate) AS tabloide_data_fim
            FROM tabloide t
            JOIN tabloide_filial tf ON tf.tabloide_id = t.tabloide_id
            JOIN produto p3 ON p3.produto_id = ?
            JOIN tabloide_grupo tg ON tg.tabloide_id = t.tabloide_id AND tg.grupo_id = p3.grupo_id
            LEFT JOIN grupo_preco_produto gpp3 ON gpp3.produto_id = p3.produto_id AND gpp3.grupo_preco_id = ?
            LEFT JOIN preco_medio_custo pmc3 ON pmc3.produto_id = p3.produto_id AND pmc3.fillogica_id = ?
            WHERE t.apagado = 'N'
              AND t.ativo = 'S'
              AND t.vigencia_ate >= CURRENT_DATE
              AND (tf.filial_id = 0 OR tf.filial_id = ?)
              AND tg.$colunaDia = 'S'
            GROUP BY p3.produto_id
        ) tbl_grupo ON tbl_grupo.produto_id = p.produto_id

        WHERE p.produto_id = ?
      ''', [
        _grupoPrecoId,        // gpp.grupo_preco_id
        _filialId,            // pfil.filial_id
        tabelaDescontoId,     // ptd.tabela_desconto_id
        produtoId,            // ptd.produto_id
        tabelaDescontoId,     // gtd.tabela_desconto_id (busca todos grupos)
        _grupoPrecoId,        // gpp2.grupo_preco_id
        _filialId,            // pmc2.fillogica_id
        _filialId,            // tf.filial_id
        produtoId,            // tdp.produto_id
        produtoId,            // p3.produto_id
        _grupoPrecoId,        // gpp3.grupo_preco_id
        _filialId,            // pmc3.fillogica_id
        _filialId,            // tf.filial_id (grupo)
        produtoId,            // p.produto_id
      ]);

      if (results.isEmpty) {
        return null;
      }

      final row = results.first;
      final precoCheio = (row['preco_cheio'] as num?)?.toDouble() ?? 0.0;

      // Precos da filial
      final precoFilialCheio = (row['preco_filial_cheio'] as num?)?.toDouble();
      final precoFilialPromo = (row['preco_filial_promo'] as num?)?.toDouble();
      final precoFilialAvista = (row['preco_filial_avista'] as num?)?.toDouble();

      // Permissoes (valores brutos do banco)
      final permPromocaoRaw = row['perm_promocao']?.toString();
      final permDescAvistaRaw = row['perm_desc_avista']?.toString();
      final permDescQtdeRaw = row['perm_desc_qtde']?.toString();
      final permTabloideRaw = row['perm_tabloide']?.toString();

      debugPrint('[PrecoPraticado] produtoId=$produtoId grupoId=$grupoId');
      debugPrint('[PrecoPraticado] Permissoes RAW: promo=$permPromocaoRaw, avista=$permDescAvistaRaw, qtde=$permDescQtdeRaw, tabloide=$permTabloideRaw');

      final permPromocao = permPromocaoRaw == 'S';
      final permDescAvista = permDescAvistaRaw == 'S';
      final permDescQtde = permDescQtdeRaw == 'S';
      final permTabloide = permTabloideRaw == 'S';

      // Descontos
      final descontoRegra = (row['desconto_regra'] as num?)?.toDouble() ?? 0.0;
      final precoCadastroPromo = (row['preco_cadastro_promo'] as num?)?.toDouble();
      final descontoAvistaCadastro = (row['desconto_avista_cadastro'] as num?)?.toDouble() ?? 0.0;

      // Datas de fim de promocao
      DateTime? dataFimPromoFilial;
      DateTime? dataFimPromoCadastro;
      final dataFilialRaw = row['data_fim_promo_filial'];
      final dataCadastroRaw = row['data_fim_promo_cadastro'];
      if (dataFilialRaw != null) {
        dataFimPromoFilial = dataFilialRaw is DateTime ? dataFilialRaw : DateTime.tryParse(dataFilialRaw.toString());
      }
      if (dataCadastroRaw != null) {
        dataFimPromoCadastro = dataCadastroRaw is DateTime ? dataCadastroRaw : DateTime.tryParse(dataCadastroRaw.toString());
      }

      // Tabloide
      final precoTabloideBruto = (row['preco_tabloide_raw'] as num?)?.toDouble();
      final precoTabloide = (precoTabloideBruto != null && precoTabloideBruto < 999999999)
          ? precoTabloideBruto : null;
      final tabloideDesc = row['tabloide_desc']?.toString();
      DateTime? dataFimTabloide;
      final dataTabloideRaw = row['tabloide_data_fim'];
      if (dataTabloideRaw != null) {
        dataFimTabloide = dataTabloideRaw is DateTime ? dataTabloideRaw : DateTime.tryParse(dataTabloideRaw.toString());
      }

      // Calcular candidatos
      final List<double> candidatos = [];
      String origemPreco = 'NORMAL';

      // Se tem preco filial, usa como base
      if (precoFilialCheio != null && precoFilialCheio > 0) {
        candidatos.add(precoFilialCheio);

        if (precoFilialPromo != null && precoFilialPromo > 0) {
          candidatos.add(precoFilialPromo);
        }

        if (precoFilialAvista != null && precoFilialAvista > 0) {
          candidatos.add(precoFilialAvista);
        }
      } else {
        // Usa preco do cadastro
        if (precoCheio > 0) {
          candidatos.add(precoCheio);

          // Promo do cadastro
          if (permPromocao && precoCadastroPromo != null && precoCadastroPromo > 0) {
            candidatos.add(precoCadastroPromo);
          }

          // Desc a vista do cadastro
          if (permDescAvista && descontoAvistaCadastro > 0) {
            candidatos.add(precoCheio * (1 - descontoAvistaCadastro / 100));
          }

          // Desconto da regra
          if (descontoRegra > 0) {
            candidatos.add(precoCheio * (1 - descontoRegra / 100));
          }

          // Tabloide
          if (permTabloide && precoTabloide != null && precoTabloide > 0) {
            candidatos.add(precoTabloide);
          }
        }
      }

      // Encontrar o menor preco
      double precoPraticado = precoCheio;
      if (candidatos.isNotEmpty) {
        precoPraticado = candidatos.reduce((a, b) => a < b ? a : b);

        // Determinar origem do preco
        if (precoFilialCheio != null && precoFilialCheio > 0) {
          if (precoFilialPromo != null && (precoPraticado - precoFilialPromo).abs() < 0.01) {
            origemPreco = 'PROMO FILIAL';
          } else if (precoFilialAvista != null && (precoPraticado - precoFilialAvista).abs() < 0.01) {
            origemPreco = 'DESC. A VISTA';
          } else {
            origemPreco = 'PRECO FILIAL';
          }
        } else {
          if (permTabloide && precoTabloide != null && (precoPraticado - precoTabloide).abs() < 0.01) {
            origemPreco = 'TABLOIDE${tabloideDesc != null ? ' - ${tabloideDesc.toUpperCase()}' : ''}';
          } else if (permPromocao && precoCadastroPromo != null && (precoPraticado - precoCadastroPromo).abs() < 0.01) {
            origemPreco = 'PROMOCAO';
          } else if (descontoRegra > 0 && (precoPraticado - (precoCheio * (1 - descontoRegra / 100))).abs() < 0.01) {
            origemPreco = 'DESC. REGRA';
          } else if (permDescAvista && descontoAvistaCadastro > 0 && (precoPraticado - (precoCheio * (1 - descontoAvistaCadastro / 100))).abs() < 0.01) {
            origemPreco = 'DESC. A VISTA';
          } else {
            origemPreco = 'NORMAL';
          }
        }
      }

      // Determinar data fim da promocao baseado na origem do preco
      DateTime? dataFimPromocao;
      if (origemPreco == 'PROMO FILIAL' && dataFimPromoFilial != null) {
        dataFimPromocao = dataFimPromoFilial;
      } else if (origemPreco == 'PROMOCAO' && dataFimPromoCadastro != null) {
        dataFimPromocao = dataFimPromoCadastro;
      } else if (origemPreco.contains('TABLOIDE') && dataFimTabloide != null) {
        dataFimPromocao = dataFimTabloide;
      }

      return {
        'preco_cheio': precoFilialCheio ?? precoCheio,
        'preco_praticado': precoPraticado,
        'origem_preco': origemPreco,
        'data_fim_promocao': dataFimPromocao?.toIso8601String(),
        'permite_desc_qtde': permDescQtde,
      };
    } catch (e, stackTrace) {
      debugPrint('[DatabaseService] Erro ao calcular preco praticado: $e');
      debugPrint('[DatabaseService] StackTrace: $stackTrace');
      return null;
    }
  }

  /// Busca regras de desconto por quantidade para um produto
  static Future<List<RegraDescontoQtde>> buscarDescontoQuantidade(int produtoId) async {
    try {
      final conn = await getConnection();
      if (conn == null || _filialId == null) return [];

      // Determinar o dia da semana para filtro
      final diaSemana = DateTime.now().weekday;
      final colunaDia = switch (diaSemana) {
        1 => 'dia_segunda',
        2 => 'dia_terca',
        3 => 'dia_quarta',
        4 => 'dia_quinta',
        5 => 'dia_sexta',
        6 => 'dia_sabado',
        7 => 'dia_domingo',
        _ => 'dia_segunda',
      };

      final results = await conn.query('''
        SELECT
          dq.qtde,
          dq.desconto
        FROM desconto_quantidade dq
        WHERE dq.produto_id = ?
          AND (dq.apagado IS NULL OR dq.apagado <> 'S')
          AND (dq.filial_id = 0 OR dq.filial_id = ?)
          AND dq.$colunaDia = 'S'
        ORDER BY dq.qtde ASC
      ''', [produtoId, _filialId]);

      final List<RegraDescontoQtde> regras = [];
      for (final row in results) {
        regras.add(RegraDescontoQtde(
          quantidade: (row['qtde'] as num?)?.toInt() ?? 1,
          desconto: (row['desconto'] as num?)?.toDouble() ?? 0,
        ));
      }

      return regras;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar desconto quantidade: $e');
      return [];
    }
  }

  /// Calcula preco com desconto quantidade escalonado
  static Map<String, dynamic> calcularPrecoDescontoQuantidade({
    required double precoCheio,
    required int quantidade,
    required List<RegraDescontoQtde> regras,
    double? precoLoja,
  }) {
    if (regras.isEmpty || quantidade <= 0) {
      return {
        'precoTotal': precoCheio * quantidade,
        'precoMedio': precoCheio,
        'economia': 0.0,
        'usandoDesconto': false,
      };
    }

    final quantidadeMaximaRegras = regras.length;
    double precoTotal = 0;
    final precoBase = precoLoja ?? precoCheio;

    for (int i = 1; i <= quantidade; i++) {
      // Posicao no ciclo (1-based)
      final posicaoNoCiclo = ((i - 1) % quantidadeMaximaRegras) + 1;

      // Buscar regra para esta posicao
      RegraDescontoQtde? regraAplicavel;
      for (final regra in regras) {
        if (regra.quantidade == posicaoNoCiclo) {
          regraAplicavel = regra;
          break;
        }
      }

      if (regraAplicavel != null && regraAplicavel.desconto > 0) {
        // Aplicar desconto sobre preco cheio
        precoTotal += precoCheio * (1 - regraAplicavel.desconto / 100);
      } else {
        // Sem regra, usa preco da loja
        precoTotal += precoBase;
      }
    }

    final precoMedio = precoTotal / quantidade;
    final precoSemDesconto = precoBase * quantidade;
    final economia = precoSemDesconto - precoTotal;

    return {
      'precoTotal': precoTotal,
      'precoMedio': precoMedio,
      'economia': economia > 0 ? economia : 0.0,
      'usandoDesconto': economia > 0,
      'ciclosCompletos': quantidade ~/ quantidadeMaximaRegras,
      'quantidadeMaxima': quantidadeMaximaRegras,
    };
  }

  /// Gera sugestao de desconto quantidade para o vendedor
  static String? gerarSugestaoDescontoQtde({
    required List<RegraDescontoQtde> regras,
    required double precoCheio,
  }) {
    if (regras.isEmpty) return null;

    // Encontrar a ultima regra (maior desconto geralmente)
    final ultimaRegra = regras.last;
    if (ultimaRegra.desconto >= 99) {
      return 'Levando ${regras.length} un, a ultima sai GRATIS!';
    } else if (ultimaRegra.desconto > 0) {
      final precoComDesconto = precoCheio * (1 - ultimaRegra.desconto / 100);
      final economia = precoCheio - precoComDesconto;
      return 'Levando ${regras.length} un, economiza R\$ ${economia.toStringAsFixed(2)} cada!';
    }

    return null;
  }

  /// Busca combos/kits disponiveis para um produto
  static Future<List<ComboDisponivel>> buscarCombosDisponiveis(int produtoId, {int? tabelaDescontoId}) async {
    try {
      final conn = await getConnection();
      if (conn == null || _filialId == null || _grupoPrecoId == null) return [];

      // Determinar o dia da semana
      final diaSemana = DateTime.now().weekday;
      final colunaDia = switch (diaSemana) {
        1 => 'dia_segunda',
        2 => 'dia_terca',
        3 => 'dia_quarta',
        4 => 'dia_quinta',
        5 => 'dia_sexta',
        6 => 'dia_sabado',
        7 => 'dia_domingo',
        _ => 'dia_segunda',
      };

      // Buscar grupo_precos_id do produto para considerar combos por grupo
      int? grupoPrecosProduto;
      final grupoProdutoResult = await conn.query('''
        SELECT grupo_precos_id FROM produto WHERE produto_id = ? AND apagado = 'N'
      ''', [produtoId]);
      if (grupoProdutoResult.isNotEmpty) {
        grupoPrecosProduto = (grupoProdutoResult.first['grupo_precos_id'] as num?)?.toInt();
      }

      // Buscar preco original do produto para calcular desconto percentual
      double precoOriginalProduto = 0;
      final precoResult = await conn.query('''
        SELECT COALESCE(gpp.preco_vnd, 0) as preco_vnd
        FROM grupo_preco_produto gpp
        WHERE gpp.produto_id = ? AND gpp.grupo_preco_id = ?
      ''', [produtoId, _grupoPrecoId]);
      if (precoResult.isNotEmpty) {
        precoOriginalProduto = (precoResult.first['preco_vnd'] as num?)?.toDouble() ?? 0;
      }

      // Buscar kits onde:
      // 1. O produto esta incluido diretamente (kit_promo_produto)
      // 2. OU o grupo de precos do produto esta incluido (kit_promo_grupo_precos)
      final results = await conn.query('''
        SELECT DISTINCT
          kp.kit_promo_id,
          kp.descricao,
          COALESCE(kpp.quantidade, kpgp.quantidade, 1) as quantidade,
          COALESCE(kpp.preco, kpgp.preco) as preco_kit,
          CASE
            WHEN kpp.produto_id IS NOT NULL THEN 'PRODUTO'
            ELSE 'GRUPO'
          END as tipo_kit
        FROM kit_promo kp
        INNER JOIN kit_promo_filial kpf ON kpf.kit_promo_id = kp.kit_promo_id
          AND (kpf.filial_id = 0 OR kpf.filial_id = ?)
          AND kpf.apagado = 'N'
        LEFT JOIN kit_promo_produto kpp ON kpp.kit_promo_id = kp.kit_promo_id
          AND kpp.produto_id = ?
          AND kpp.apagado = 'N'
        LEFT JOIN kit_promo_grupo_precos kpgp ON kpgp.kit_promo_id = kp.kit_promo_id
          AND kpgp.grupo_precos_id = ?
          AND kpgp.apagado = 'N'
        WHERE kp.apagado = 'N'
          AND kp.ativo = 'S'
          AND kp.venda_apenas_cod_kitpromo = 'N'
          AND kp.vigencia_de <= CURRENT_DATE
          AND kp.vigencia_ate >= CURRENT_DATE
          AND kp.$colunaDia = 'S'
          AND (kpp.produto_id IS NOT NULL OR kpgp.grupo_precos_id IS NOT NULL)
        ORDER BY kp.descricao
        LIMIT 5
      ''', [_filialId, produtoId, grupoPrecosProduto]);

      final List<ComboDisponivel> combos = [];
      for (final row in results) {
        final kitPromoId = (row['kit_promo_id'] as num?)?.toInt() ?? 0;
        final precoKit = (row['preco_kit'] as num?)?.toDouble();
        final qtdMinima = (row['quantidade'] as num?)?.toInt() ?? 1;

        // Calcular desconto percentual se tem preco do kit
        double descontoPerc = 0;
        if (precoKit != null && precoKit > 0 && precoOriginalProduto > 0) {
          descontoPerc = ((precoOriginalProduto - precoKit) / precoOriginalProduto) * 100;
          if (descontoPerc < 0) descontoPerc = 0;
        }

        // Buscar produtos do combo
        final produtosCombo = await _buscarProdutosDoCombo(conn, kitPromoId);

        // Buscar grupos de preco do combo
        final gruposPrecoCombo = await _buscarGruposPrecoDoCombo(conn, kitPromoId);

        combos.add(ComboDisponivel(
          kitPromoId: kitPromoId,
          descricao: row['descricao']?.toString() ?? '',
          qtdMinima: qtdMinima,
          descontoPerc: descontoPerc,
          precoFixo: precoKit,
          produtos: produtosCombo,
          gruposPreco: gruposPrecoCombo,
        ));
      }

      return combos;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar combos: $e');
      return [];
    }
  }

  /// Busca os produtos de um combo/kit
  static Future<List<ComboProduto>> _buscarProdutosDoCombo(MySqlConnection conn, int kitPromoId) async {
    try {
      final results = await conn.query('''
        SELECT
          kpp.produto_id,
          p.descricao,
          p.barras,
          COALESCE(kpp.quantidade, 1) as quantidade,
          COALESCE(gpp.preco_vnd, 0) as preco_original,
          kpp.preco as preco_kit
        FROM kit_promo_produto kpp
        INNER JOIN produto p ON p.produto_id = kpp.produto_id AND p.apagado = 'N'
        LEFT JOIN grupo_preco_produto gpp ON gpp.produto_id = kpp.produto_id AND gpp.grupo_preco_id = ?
        WHERE kpp.kit_promo_id = ?
          AND kpp.apagado = 'N'
        ORDER BY p.descricao
        LIMIT 10
      ''', [_grupoPrecoId, kitPromoId]);

      final List<ComboProduto> produtos = [];
      for (final row in results) {
        final precoOriginal = (row['preco_original'] as num?)?.toDouble() ?? 0;
        final precoKit = (row['preco_kit'] as num?)?.toDouble();

        // Calcular desconto percentual
        double descontoPerc = 0;
        if (precoKit != null && precoKit > 0 && precoOriginal > 0) {
          descontoPerc = ((precoOriginal - precoKit) / precoOriginal) * 100;
          if (descontoPerc < 0) descontoPerc = 0;
        }

        produtos.add(ComboProduto(
          produtoId: (row['produto_id'] as num?)?.toInt() ?? 0,
          descricao: row['descricao']?.toString() ?? '',
          barras: row['barras']?.toString(),
          qtdMinima: (row['quantidade'] as num?)?.toInt() ?? 1,
          precoOriginal: precoOriginal,
          precoKit: precoKit,
          descontoPerc: descontoPerc,
        ));
      }

      return produtos;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar produtos do combo: $e');
      return [];
    }
  }

  /// Busca os grupos de preco de um combo/kit
  static Future<List<ComboGrupoPreco>> _buscarGruposPrecoDoCombo(MySqlConnection conn, int kitPromoId) async {
    try {
      final results = await conn.query('''
        SELECT
          kpgp.grupo_precos_id,
          gp.descricao,
          COALESCE(kpgp.quantidade, 1) as quantidade,
          kpgp.preco as preco_kit,
          (SELECT COUNT(*) FROM produto p2
           WHERE p2.grupo_precos_id = kpgp.grupo_precos_id
           AND p2.apagado = 'N' AND p2.inativo = 'N') as qtd_produtos
        FROM kit_promo_grupo_precos kpgp
        INNER JOIN grupo_precos gp ON gp.grupo_precos_id = kpgp.grupo_precos_id
        WHERE kpgp.kit_promo_id = ?
          AND kpgp.apagado = 'N'
        ORDER BY gp.descricao
        LIMIT 5
      ''', [kitPromoId]);

      final List<ComboGrupoPreco> grupos = [];
      for (final row in results) {
        grupos.add(ComboGrupoPreco(
          grupoPrecoId: (row['grupo_precos_id'] as num?)?.toInt() ?? 0,
          descricao: row['descricao']?.toString() ?? '',
          qtdMinima: (row['quantidade'] as num?)?.toInt() ?? 1,
          precoKit: (row['preco_kit'] as num?)?.toDouble(),
          qtdProdutosNoGrupo: (row['qtd_produtos'] as num?)?.toInt() ?? 0,
        ));
      }

      return grupos;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar grupos de preco do combo: $e');
      return [];
    }
  }

  /// Busca lotes com desconto para um produto
  /// Omite lotes proximos ao vencimento (< 30 dias) para exibicao ao cliente
  static Future<List<LoteDesconto>> buscarLotesComDesconto(int produtoId, {bool omitirProximoVencimento = true}) async {
    try {
      final conn = await getConnection();
      if (conn == null || _filialId == null) return [];

      // Buscar lotes com desconto configurado (excluindo proximos ao vencimento para cliente)
      final results = await conn.query('''
        SELECT
          ln.lote_novo_id,
          ln.lote,
          ln.validade,
          COALESCE(lndc.perc_desconto, 0) as perc_desconto,
          COALESCE(ln.estoque, 0) as estoque
        FROM lote_novo ln
        INNER JOIN lote_novo_desc_comissao lndc ON lndc.lote_novo_id = ln.lote_novo_id
          AND lndc.fillogica_id = ?
          AND (lndc.apagado IS NULL OR lndc.apagado = 'N')
        WHERE ln.produto_id = ?
          AND ln.fillogica_id = ?
          AND (ln.apagado IS NULL OR ln.apagado = 'N')
          AND lndc.perc_desconto > 0
          AND COALESCE(ln.estoque, 0) > 0
          ${omitirProximoVencimento ? "AND (ln.validade IS NULL OR ln.validade > DATE_ADD(CURRENT_DATE, INTERVAL 30 DAY))" : ""}
        ORDER BY lndc.perc_desconto DESC
        LIMIT 5
      ''', [_filialId, produtoId, _filialId]);

      final List<LoteDesconto> lotes = [];
      for (final row in results) {
        final validadeRaw = row['validade'];
        DateTime? validade;
        if (validadeRaw != null) {
          if (validadeRaw is DateTime) {
            validade = validadeRaw;
          } else {
            validade = DateTime.tryParse(validadeRaw.toString());
          }
        }

        lotes.add(LoteDesconto(
          loteNovoId: (row['lote_novo_id'] as num?)?.toInt() ?? 0,
          lote: row['lote']?.toString() ?? '',
          validade: validade,
          percDesconto: (row['perc_desconto'] as num?)?.toDouble() ?? 0,
          estoque: (row['estoque'] as num?)?.toInt() ?? 0,
        ));
      }

      return lotes;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar lotes com desconto: $e');
      return [];
    }
  }

  /// Busca combos/kits ativos para exibicao no carrossel
  static Future<List<Map<String, dynamic>>> buscarCombosParaCarrossel({
    required bool somenteComEstoque,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null || _filialId == null || _grupoPrecoId == null) return [];

      // Determinar o dia da semana
      final diaSemana = DateTime.now().weekday;
      final colunaDia = switch (diaSemana) {
        1 => 'dia_segunda',
        2 => 'dia_terca',
        3 => 'dia_quarta',
        4 => 'dia_quinta',
        5 => 'dia_sexta',
        6 => 'dia_sabado',
        7 => 'dia_domingo',
        _ => 'dia_segunda',
      };

      // Buscar kits/combos ativos
      final results = await conn.query('''
        SELECT DISTINCT
          kp.kit_promo_id,
          kp.descricao,
          kp.vigencia_ate,
          (
            SELECT GROUP_CONCAT(
              CONCAT(
                COALESCE(p.descricao, gp.descricao),
                ' (', COALESCE(kpp2.quantidade, kpgp2.quantidade, 1), ')'
              )
              SEPARATOR ' + '
            )
            FROM kit_promo kp2
            LEFT JOIN kit_promo_produto kpp2 ON kpp2.kit_promo_id = kp2.kit_promo_id AND kpp2.apagado = 'N'
            LEFT JOIN produto p ON p.produto_id = kpp2.produto_id AND p.apagado = 'N'
            LEFT JOIN kit_promo_grupo_precos kpgp2 ON kpgp2.kit_promo_id = kp2.kit_promo_id AND kpgp2.apagado = 'N'
            LEFT JOIN grupo_precos gp ON gp.grupo_precos_id = kpgp2.grupo_precos_id
            WHERE kp2.kit_promo_id = kp.kit_promo_id
            LIMIT 3
          ) as produtos_resumo,
          (
            SELECT COUNT(DISTINCT COALESCE(kpp3.produto_id, kpgp3.grupo_precos_id))
            FROM kit_promo kp3
            LEFT JOIN kit_promo_produto kpp3 ON kpp3.kit_promo_id = kp3.kit_promo_id AND kpp3.apagado = 'N'
            LEFT JOIN kit_promo_grupo_precos kpgp3 ON kpgp3.kit_promo_id = kp3.kit_promo_id AND kpgp3.apagado = 'N'
            WHERE kp3.kit_promo_id = kp.kit_promo_id
          ) as qtd_itens
        FROM kit_promo kp
        INNER JOIN kit_promo_filial kpf ON kpf.kit_promo_id = kp.kit_promo_id
          AND (kpf.filial_id = 0 OR kpf.filial_id = ?)
          AND kpf.apagado = 'N'
        WHERE kp.apagado = 'N'
          AND kp.ativo = 'S'
          AND kp.venda_apenas_cod_kitpromo = 'N'
          AND kp.vigencia_de <= CURRENT_DATE
          AND kp.vigencia_ate >= CURRENT_DATE
          AND kp.$colunaDia = 'S'
        ORDER BY kp.descricao
      ''', [_filialId]);

      final List<Map<String, dynamic>> combos = [];
      for (final row in results) {
        final kitPromoId = (row['kit_promo_id'] as num?)?.toInt() ?? 0;
        final descricao = row['descricao']?.toString() ?? '';
        final produtosResumo = row['produtos_resumo']?.toString() ?? '';
        final qtdItens = (row['qtd_itens'] as num?)?.toInt() ?? 0;

        // Buscar todos os produtos do combo
        final produtosCombo = await _buscarProdutosDoComboParaCarrossel(
          conn,
          kitPromoId,
        );

        // Buscar grupos de preco do combo
        final gruposPrecoCombo = await _buscarGruposPrecoDoComboParaCarrossel(
          conn,
          kitPromoId,
        );

        // Verificar estoque se necessario
        if (somenteComEstoque) {
          // Regra 1: TODOS os produtos diretos devem ter estoque >= quantidade necessaria
          if (produtosCombo.isNotEmpty) {
            final todosProdutosTenhoEstoque = produtosCombo.every(
              (p) => (p['estoque'] as int? ?? 0) >= (p['quantidade'] as int? ?? 1)
            );
            if (!todosProdutosTenhoEstoque) {
              continue; // Pular combo se algum produto nao tem estoque suficiente
            }
          }

          // Regra 2: Para grupos de preco, ALGUM produto do grupo deve ter estoque
          if (gruposPrecoCombo.isNotEmpty) {
            final algumGrupoTemEstoque = gruposPrecoCombo.any(
              (g) => (g['temProdutoComEstoque'] as bool? ?? false)
            );
            if (!algumGrupoTemEstoque) {
              continue; // Pular combo se nenhum grupo tem produto com estoque
            }
          }
        }

        // Pular combos sem produtos e sem grupos
        if (produtosCombo.isEmpty && gruposPrecoCombo.isEmpty) {
          continue;
        }

        // Calcular data fim
        DateTime? dataFim;
        int? diasRestantes;
        final vigenciaAte = row['vigencia_ate'];
        if (vigenciaAte != null) {
          if (vigenciaAte is DateTime) {
            dataFim = vigenciaAte;
          } else {
            dataFim = DateTime.tryParse(vigenciaAte.toString());
          }
          if (dataFim != null) {
            final hoje = DateTime.now();
            final hojeApenasDia = DateTime(hoje.year, hoje.month, hoje.day);
            final fimApenasDia = DateTime(dataFim.year, dataFim.month, dataFim.day);
            diasRestantes = fimApenasDia.difference(hojeApenasDia).inDays;
          }
        }

        combos.add({
          'kitPromoId': kitPromoId,
          'descricao': descricao,
          'produtosResumo': produtosResumo,
          'qtdItens': qtdItens,
          'produtos': produtosCombo,
          'gruposPreco': gruposPrecoCombo,
          'dataFim': dataFim?.toIso8601String(),
          'diasRestantes': diasRestantes,
          'isCombo': true,
        });
      }

      debugPrint('[Carrossel DB] Combos encontrados: ${combos.length}');
      return combos;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar combos para carrossel: $e');
      return [];
    }
  }

  /// Busca produtos de um combo para exibicao no carrossel
  static Future<List<Map<String, dynamic>>> _buscarProdutosDoComboParaCarrossel(
    MySqlConnection conn,
    int kitPromoId,
  ) async {
    try {
      // Buscar TODOS os produtos do combo
      final results = await conn.query('''
        SELECT
          kpp.produto_id,
          p.descricao,
          COALESCE(kpp.quantidade, 1) as quantidade,
          COALESCE(gpp.preco_vnd, 0) as preco_original,
          kpp.preco as preco_kit,
          COALESCE(em.estoque, 0) as estoque
        FROM kit_promo_produto kpp
        INNER JOIN produto p ON p.produto_id = kpp.produto_id AND p.apagado = 'N'
        LEFT JOIN grupo_preco_produto gpp ON gpp.produto_id = kpp.produto_id AND gpp.grupo_preco_id = ?
        LEFT JOIN estoque_minimo em ON em.produto_id = kpp.produto_id AND em.filial_id = ?
        WHERE kpp.kit_promo_id = ?
          AND kpp.apagado = 'N'
        ORDER BY p.descricao
      ''', [_grupoPrecoId, _filialId, kitPromoId]);

      final List<Map<String, dynamic>> produtos = [];
      for (final row in results) {
        final precoOriginal = (row['preco_original'] as num?)?.toDouble() ?? 0;
        final precoKit = (row['preco_kit'] as num?)?.toDouble();

        // Calcular desconto percentual
        double descontoPerc = 0;
        if (precoKit != null && precoKit > 0 && precoOriginal > 0) {
          descontoPerc = ((precoOriginal - precoKit) / precoOriginal) * 100;
          if (descontoPerc < 0) descontoPerc = 0;
        }

        produtos.add({
          'produtoId': (row['produto_id'] as num?)?.toInt() ?? 0,
          'descricao': row['descricao']?.toString() ?? '',
          'quantidade': (row['quantidade'] as num?)?.toInt() ?? 1,
          'precoOriginal': precoOriginal,
          'precoKit': precoKit,
          'descontoPerc': descontoPerc,
          'estoque': (row['estoque'] as num?)?.toInt() ?? 0,
        });
      }

      return produtos;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar produtos do combo para carrossel: $e');
      return [];
    }
  }

  /// Busca grupos de preco de um combo e verifica se tem produtos com estoque
  static Future<List<Map<String, dynamic>>> _buscarGruposPrecoDoComboParaCarrossel(
    MySqlConnection conn,
    int kitPromoId,
  ) async {
    try {
      // Buscar grupos de preco do combo
      final results = await conn.query('''
        SELECT
          kpgp.grupo_precos_id,
          gp.descricao,
          COALESCE(kpgp.quantidade, 1) as quantidade,
          kpgp.preco as preco_kit,
          (
            SELECT COUNT(*)
            FROM produto p2
            INNER JOIN estoque_minimo em2 ON em2.produto_id = p2.produto_id AND em2.filial_id = ?
            WHERE p2.grupo_precos_id = kpgp.grupo_precos_id
              AND p2.apagado = 'N'
              AND p2.inativo = 'N'
              AND em2.estoque >= COALESCE(kpgp.quantidade, 1)
          ) as qtd_produtos_com_estoque
        FROM kit_promo_grupo_precos kpgp
        INNER JOIN grupo_precos gp ON gp.grupo_precos_id = kpgp.grupo_precos_id
        WHERE kpgp.kit_promo_id = ?
          AND kpgp.apagado = 'N'
        ORDER BY gp.descricao
      ''', [_filialId, kitPromoId]);

      final List<Map<String, dynamic>> grupos = [];
      for (final row in results) {
        final qtdProdutosComEstoque = (row['qtd_produtos_com_estoque'] as num?)?.toInt() ?? 0;

        grupos.add({
          'grupoPrecoId': (row['grupo_precos_id'] as num?)?.toInt() ?? 0,
          'descricao': row['descricao']?.toString() ?? '',
          'quantidade': (row['quantidade'] as num?)?.toInt() ?? 1,
          'precoKit': (row['preco_kit'] as num?)?.toDouble(),
          'temProdutoComEstoque': qtdProdutosComEstoque > 0,
        });
      }

      return grupos;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar grupos de preco do combo: $e');
      return [];
    }
  }

  /// Busca todas as tabelas de desconto disponíveis
  static Future<List<Map<String, dynamic>>> buscarTabelasDesconto() async {
    try {
      final conn = await getConnection();
      if (conn == null) return [];

      final results = await conn.query('''
        SELECT
          tabela_desconto_id,
          descricao
        FROM tabela_desconto
        WHERE apagado = 'N'
        ORDER BY descricao
      ''');

      final List<Map<String, dynamic>> tabelas = [];

      for (final row in results) {
        tabelas.add({
          'id': (row['tabela_desconto_id'] as num?)?.toInt() ?? 0,
          'descricao': row['descricao']?.toString() ?? '',
        });
      }

      return tabelas;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar tabelas de desconto: $e');
      return [];
    }
  }

  /// Pesquisa produtos por texto (descricao, codigo de barras, fabricante)
  /// Retorna lista de produtos para selecao
  /// Com ordenacao inteligente: produtos com estoque e promoções primeiro
  static Future<List<Map<String, dynamic>>> pesquisarProdutos(
    String termo, {
    int? tabelaDescontoId,
    bool somenteComEstoque = false,
    int limite = 30,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null) return [];

      if (_filialId == null || _grupoPrecoId == null) return [];

      // Normalizar termo de pesquisa (remover acentos para busca mais flexivel)
      final termoNormalizado = _normalizarTexto(termo);
      final searchTerm = '%$termoNormalizado%';
      final searchTermOriginal = '%$termo%';

      // Filtro de estoque
      final filtroEstoque = somenteComEstoque ? 'AND COALESCE(em.estoque, 0) > 0' : '';

      // Query com ordenacao inteligente:
      // 1. Produtos com promoções/descontos especiais primeiro
      // 2. Produtos com estoque antes dos sem estoque
      // 3. Match no inicio do nome antes de match no meio
      final results = await conn.query('''
        SELECT DISTINCT
          p.Produto_id,
          p.descricao,
          p.barras,
          p.grupo_id,
          f.descricao as fabricante_nome,
          COALESCE(em.estoque, 0) as estoque,
          COALESCE(gpp.preco_vnd, 0) as preco_vnd,
          CASE WHEN EXISTS (
            SELECT 1 FROM desconto_quantidade dq
            WHERE dq.produto_id = p.Produto_id
              AND dq.filial_id = ?
              AND dq.apagado = 'N'
          ) THEN 1 ELSE 0 END as tem_desc_qtde,
          CASE WHEN EXISTS (
            SELECT 1 FROM lote_novo ln
            INNER JOIN lote_novo_desc_comissao lndc ON lndc.lote_novo_id = ln.lote_novo_id
              AND lndc.fillogica_id = ?
              AND (lndc.apagado IS NULL OR lndc.apagado = 'N')
            WHERE ln.produto_id = p.Produto_id
              AND ln.fillogica_id = ?
              AND (ln.apagado IS NULL OR ln.apagado = 'N')
              AND lndc.perc_desconto > 0
              AND COALESCE(ln.estoque, 0) > 0
          ) THEN 1 ELSE 0 END as tem_lote_especial
        FROM produto p
        LEFT JOIN fabricantes f ON f.fabricantes_id = p.fabricantes_id AND f.apagado = 'N'
        LEFT JOIN estoque_minimo em ON em.produto_id = p.Produto_id AND em.filial_id = ?
        LEFT JOIN grupo_preco_produto gpp ON gpp.produto_id = p.Produto_id AND gpp.grupo_preco_id = ?
        LEFT JOIN barras b ON b.produto_id = p.Produto_id AND b.apagado = 'N'
        WHERE p.apagado = 'N'
          AND p.inativo = 'N'
          $filtroEstoque
          AND (
            p.descricao LIKE ?
            OR p.descricao LIKE ?
            OR p.barras LIKE ?
            OR p.barras LIKE ?
            OR b.barras LIKE ?
            OR b.barras LIKE ?
            OR f.descricao LIKE ?
            OR f.descricao LIKE ?
            OR CAST(p.Produto_id AS CHAR) = ?
          )
        ORDER BY
          tem_lote_especial DESC,
          tem_desc_qtde DESC,
          CASE WHEN COALESCE(em.estoque, 0) > 0 THEN 0 ELSE 1 END,
          CASE
            WHEN p.descricao LIKE ? THEN 1
            WHEN p.descricao LIKE ? THEN 2
            WHEN p.descricao LIKE ? THEN 3
            ELSE 4
          END,
          p.descricao
        LIMIT ?
      ''', [
        _filialId,           // tem_desc_qtde subquery
        _filialId,           // lndc.fillogica_id no lote subquery
        _filialId,           // ln.fillogica_id no lote subquery
        _filialId,           // estoque
        _grupoPrecoId,       // preco
        searchTermOriginal,  // descricao original
        searchTerm,          // descricao normalizado
        searchTermOriginal,  // barras original
        searchTerm,          // barras normalizado
        searchTermOriginal,  // b.barras original
        searchTerm,          // b.barras normalizado
        searchTermOriginal,  // fabricante original
        searchTerm,          // fabricante normalizado
        termo,               // produto_id exato
        '$termo%',           // ORDER: comeca com original
        '$termoNormalizado%', // ORDER: comeca com normalizado
        searchTermOriginal,  // ORDER: contem original
        limite,
      ]);

      final List<Map<String, dynamic>> produtos = [];

      for (final row in results) {
        final produtoId = (row['Produto_id'] as num?)?.toInt() ?? 0;
        final grupoId = (row['grupo_id'] as num?)?.toInt() ?? 0;
        final precoVnd = (row['preco_vnd'] as num?)?.toDouble() ?? 0;
        final estoque = (row['estoque'] as num?)?.toInt() ?? 0;
        final temDescQtde = (row['tem_desc_qtde'] as num?)?.toInt() == 1;
        final temLoteEspecial = (row['tem_lote_especial'] as num?)?.toInt() == 1;

        double precoPraticado = precoVnd;
        double precoCheio = precoVnd;
        String origemPreco = 'NORMAL';
        bool isPromocional = false;

        if (tabelaDescontoId != null && tabelaDescontoId > 0) {
          final precosCalculados = await _calcularPrecoPraticado(
            produtoId: produtoId,
            grupoId: grupoId,
            tabelaDescontoId: tabelaDescontoId,
          );

          if (precosCalculados != null) {
            precoCheio = precosCalculados['preco_cheio'] as double;
            precoPraticado = precosCalculados['preco_praticado'] as double;
            origemPreco = precosCalculados['origem_preco'] as String? ?? 'NORMAL';
            isPromocional = precoPraticado < precoCheio;
          }
        }

        produtos.add({
          'produtoId': produtoId,
          'descricao': row['descricao']?.toString() ?? '',
          'barras': row['barras']?.toString() ?? '',
          'grupoId': grupoId,
          'fabricanteNome': row['fabricante_nome']?.toString() ?? '',
          'estoque': estoque,
          'precoPraticado': precoPraticado,
          'precoCheio': precoCheio,
          'origemPreco': origemPreco,
          'isPromocional': isPromocional,
          'temDescontoQuantidade': temDescQtde,
          'temLoteEspecial': temLoteEspecial,
        });
      }

      return produtos;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao pesquisar produtos: $e');
      return [];
    }
  }

  /// Busca todos os grupos de produtos para selecao
  static Future<List<Map<String, dynamic>>> buscarGruposProdutos() async {
    try {
      final conn = await getConnection();
      if (conn == null) return [];

      final results = await conn.query('''
        SELECT
          grupo_id,
          descricao
        FROM grupo
        WHERE apagado = 'N'
        ORDER BY descricao
        LIMIT 500
      ''');

      return results.map((row) => {
        'id': (row['grupo_id'] as num?)?.toInt() ?? 0,
        'descricao': row['descricao']?.toString() ?? '',
      }).toList();
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar grupos de produtos: $e');
      return [];
    }
  }

  /// Busca todas as especificacoes para selecao
  static Future<List<Map<String, dynamic>>> buscarEspecificacoes() async {
    try {
      final conn = await getConnection();
      if (conn == null) return [];

      final results = await conn.query('''
        SELECT
          especificacao_id,
          descricao
        FROM especificacao
        WHERE apagado = 'N'
        ORDER BY descricao
        LIMIT 500
      ''');

      return results.map((row) => {
        'id': (row['especificacao_id'] as num?)?.toInt() ?? 0,
        'descricao': row['descricao']?.toString() ?? '',
      }).toList();
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar especificacoes: $e');
      return [];
    }
  }

  /// Busca todos os principios ativos para selecao
  static Future<List<Map<String, dynamic>>> buscarPrincipiosAtivos() async {
    try {
      final conn = await getConnection();
      if (conn == null) return [];

      final results = await conn.query('''
        SELECT
          principio_ativo_id,
          descricao
        FROM principio_ativo
        WHERE apagado = 'N'
        ORDER BY descricao
        LIMIT 500
      ''');

      return results.map((row) => {
        'id': (row['principio_ativo_id'] as num?)?.toInt() ?? 0,
        'descricao': row['descricao']?.toString() ?? '',
      }).toList();
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar principios ativos: $e');
      return [];
    }
  }

  /// Busca produtos para exibicao em carrossel de promocoes
  /// Filtrado por grupo, especificacao ou principio ativo
  static Future<List<Map<String, dynamic>>> buscarProdutosParaCarrossel({
    required String tipoFiltro, // 'grupo', 'especificacao', 'principio_ativo'
    required List<int> ids,
    required String filtroEstoqueDesconto, // 'todos', 'estoque', 'desconto', 'estoque_desconto'
    int? tabelaDescontoId,
    int limite = 50,
  }) async {
    try {
      final conn = await getConnection();
      if (conn == null || _filialId == null || _grupoPrecoId == null) return [];

      if (ids.isEmpty) return [];

      // Construir clausula WHERE baseada no tipo de filtro
      String clausulaFiltro;
      switch (tipoFiltro) {
        case 'grupo':
          clausulaFiltro = 'p.grupo_id IN (${ids.join(',')})';
          break;
        case 'especificacao':
          clausulaFiltro = 'p.especificacao_id IN (${ids.join(',')})';
          break;
        case 'principio_ativo':
          clausulaFiltro = 'p.principio_ativo_id IN (${ids.join(',')})';
          break;
        default:
          return [];
      }

      // Construir filtro de estoque (desconto sera filtrado em Dart apos calcular precos)
      String filtroAdicional = '';
      bool filtrarDesconto = false;

      switch (filtroEstoqueDesconto) {
        case 'estoque':
          filtroAdicional = 'AND COALESCE(em.estoque, 0) > 0';
          break;
        case 'desconto':
          // Desconto sera verificado apos calcular precos (inclui tabela_desconto)
          filtrarDesconto = true;
          break;
        case 'estoque_desconto':
          filtroAdicional = 'AND COALESCE(em.estoque, 0) > 0';
          filtrarDesconto = true;
          break;
      }

      debugPrint('[Carrossel DB] ===== BUSCA CARROSSEL =====');
      debugPrint('[Carrossel DB] Tipo filtro: $tipoFiltro');
      debugPrint('[Carrossel DB] IDs recebidos: $ids');
      debugPrint('[Carrossel DB] Clausula filtro: $clausulaFiltro');
      debugPrint('[Carrossel DB] Filtro estoque/desconto: $filtroEstoqueDesconto');
      debugPrint('[Carrossel DB] filtrarDesconto: $filtrarDesconto');
      debugPrint('[Carrossel DB] filialId: $_filialId, grupoPrecoId: $_grupoPrecoId');

      // Se vamos filtrar desconto em Dart, buscar mais produtos para ter candidatos
      final limiteQuery = filtrarDesconto ? limite * 5 : limite;

      final results = await conn.query('''
        SELECT
          p.Produto_id,
          p.descricao,
          p.barras,
          p.grupo_id,
          f.descricao as fabricante_nome,
          COALESCE(em.estoque, 0) as estoque,
          COALESCE(gpp.preco_vnd, 0) as preco_vnd,
          gpp.preco_pro,
          gpp.valid_pro
        FROM produto p
        LEFT JOIN fabricantes f ON f.fabricantes_id = p.fabricantes_id AND f.apagado = 'N'
        LEFT JOIN estoque_minimo em ON em.produto_id = p.Produto_id AND em.filial_id = ?
        LEFT JOIN grupo_preco_produto gpp ON gpp.produto_id = p.Produto_id AND gpp.grupo_preco_id = ?
        WHERE p.apagado = 'N'
          AND p.inativo = 'N'
          AND $clausulaFiltro
          $filtroAdicional
        ORDER BY RAND()
        LIMIT ?
      ''', [_filialId, _grupoPrecoId, limiteQuery]);

      debugPrint('[Carrossel DB] Query retornou ${results.length} produtos');

      final List<Map<String, dynamic>> produtos = [];
      int produtosSemDesconto = 0;

      for (final row in results) {
        final produtoId = (row['Produto_id'] as num?)?.toInt() ?? 0;
        final grupoId = (row['grupo_id'] as num?)?.toInt() ?? 0;
        final precoVnd = (row['preco_vnd'] as num?)?.toDouble() ?? 0;
        final descricao = row['descricao']?.toString() ?? '';

        double precoPraticado = precoVnd;
        double precoCheio = precoVnd;
        String origemPreco = 'NORMAL';
        bool isPromocional = false;
        DateTime? dataFimPromocao;
        int? diasRestantesPromocao;
        bool permiteDescQtde = false;

        if (tabelaDescontoId != null && tabelaDescontoId > 0) {
          debugPrint('[Carrossel DB] Calculando preco para produto $produtoId...');
          final precosCalculados = await _calcularPrecoPraticado(
            produtoId: produtoId,
            grupoId: grupoId,
            tabelaDescontoId: tabelaDescontoId,
          );

          if (precosCalculados != null) {
            debugPrint('[Carrossel DB] precosCalculados: $precosCalculados');
            precoCheio = precosCalculados['preco_cheio'] as double;
            precoPraticado = precosCalculados['preco_praticado'] as double;
            origemPreco = precosCalculados['origem_preco'] as String? ?? 'NORMAL';
            isPromocional = precoPraticado < precoCheio;
            permiteDescQtde = precosCalculados['permite_desc_qtde'] as bool? ?? false;
            debugPrint('[Carrossel DB] Produto $produtoId: cheio=$precoCheio, praticado=$precoPraticado, permiteDescQtde=$permiteDescQtde');

            // Capturar data fim da promocao
            final dataFimStr = precosCalculados['data_fim_promocao'] as String?;
            if (dataFimStr != null) {
              dataFimPromocao = DateTime.tryParse(dataFimStr);
              if (dataFimPromocao != null) {
                // Comparar apenas datas, sem horas
                final hoje = DateTime.now();
                final hojeApenasDia = DateTime(hoje.year, hoje.month, hoje.day);
                final fimApenasDia = DateTime(dataFimPromocao.year, dataFimPromocao.month, dataFimPromocao.day);
                diasRestantesPromocao = fimApenasDia.difference(hojeApenasDia).inDays;
              }
            }
          } else {
            debugPrint('[Carrossel DB] precosCalculados retornou NULL para produto $produtoId');
          }
        }

        // Buscar info de desconto quantidade para este produto (so se permitido)
        String? tipoDescontoQtde;
        int? qtdeCaixaGratis;
        bool temDescontoQuantidade = false;
        double? precoUnitarioComDescQtde;
        double? descontoQtdePercentual;
        int? qtdeMinimaDesconto;
        String? textoDescontoQtde;

        // So buscar desconto quantidade se permitido pela tabela de desconto
        final regrasDescontoQtde = permiteDescQtde ? await buscarDescontoQuantidade(produtoId) : <RegraDescontoQtde>[];
        if (regrasDescontoQtde.isNotEmpty) {
          // Criar mapa qtde -> desconto para acesso rapido
          final Map<int, double> descontoPorQtde = {};
          int quantidadeMaxima = 0;
          for (final regra in regrasDescontoQtde) {
            final qtde = regra.quantidade;
            descontoPorQtde[qtde] = regra.desconto;
            if (qtde > quantidadeMaxima) {
              quantidadeMaxima = qtde;
            }
          }

          // Verificar se ultima unidade e gratis (caixa gratis)
          final descontoUltimaQtde = descontoPorQtde[quantidadeMaxima] ?? 0;
          final ultimaUnidadeGratis = descontoUltimaQtde >= 99;

          // Calcular preco medio para ciclo completo
          double totalCiclo = 0;
          int unidadesPagas = 0;
          for (int pos = 1; pos <= quantidadeMaxima; pos++) {
            final desconto = descontoPorQtde[pos] ?? 0;
            final precoUnidade = precoCheio * (1 - desconto / 100);
            totalCiclo += precoUnidade;
            if (desconto < 99) {
              unidadesPagas++;
            }
          }

          final precoMedioDescQtde = totalCiclo / quantidadeMaxima;

          // SO considera desconto quantidade se for MELHOR que o preco praticado (promocional)
          // Margem de 0.01 para evitar problemas de arredondamento
          if (precoMedioDescQtde < (precoPraticado - 0.01)) {
            temDescontoQuantidade = true;
            precoUnitarioComDescQtde = precoMedioDescQtde;
            qtdeMinimaDesconto = quantidadeMaxima;
            descontoQtdePercentual = precoCheio > 0
                ? ((precoCheio - precoUnitarioComDescQtde) / precoCheio * 100)
                : 0;

            if (ultimaUnidadeGratis) {
              tipoDescontoQtde = 'caixa_gratis';
              textoDescontoQtde = 'LEVE $quantidadeMaxima PAGUE $unidadesPagas';
            } else {
              tipoDescontoQtde = 'progressivo';
              textoDescontoQtde = 'LEVE $quantidadeMaxima c/ ${descontoQtdePercentual.toStringAsFixed(0)}% OFF';
            }
          }
          // Se preco praticado for melhor ou igual, nao destaca desconto quantidade
        }

        // Se precisa filtrar por desconto, pular produtos sem NENHUM tipo de desconto
        // (considera promocional OU desconto quantidade)
        if (filtrarDesconto && !isPromocional && !temDescontoQuantidade) {
          produtosSemDesconto++;
          continue;
        }

        produtos.add({
          'produtoId': produtoId,
          'descricao': descricao,
          'barras': row['barras']?.toString() ?? '',
          'fabricanteNome': row['fabricante_nome']?.toString() ?? '',
          'estoque': (row['estoque'] as num?)?.toInt() ?? 0,
          'precoPraticado': precoPraticado,
          'precoCheio': precoCheio,
          'origemPreco': origemPreco,
          'isPromocional': isPromocional,
          'dataFimPromocao': dataFimPromocao?.toIso8601String(),
          'diasRestantesPromocao': diasRestantesPromocao,
          'temDescontoQuantidade': temDescontoQuantidade,
          'tipoDescontoQtde': tipoDescontoQtde,
          'qtdeCaixaGratis': qtdeCaixaGratis,
          'precoUnitarioComDescQtde': precoUnitarioComDescQtde,
          'descontoQtdePercentual': descontoQtdePercentual,
          'qtdeMinimaDesconto': qtdeMinimaDesconto,
          'textoDescontoQtde': textoDescontoQtde,
        });

        // Parar quando atingir o limite desejado
        if (produtos.length >= limite) break;
      }

      debugPrint('[Carrossel DB] Produtos com desconto encontrados: ${produtos.length}');
      if (filtrarDesconto) {
        debugPrint('[Carrossel DB] Produtos pulados (sem desconto): $produtosSemDesconto');
      }

      return produtos;
    } catch (e) {
      debugPrint('[DatabaseService] Erro ao buscar produtos para carrossel: $e');
      return [];
    }
  }

  /// Normaliza texto removendo acentos para busca mais flexivel
  static String _normalizarTexto(String texto) {
    const comAcento = 'àáâãäåèéêëìíîïòóôõöùúûüçÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÇ';
    const semAcento = 'aaaaaaeeeeiiiiooooouuuucAAAAAAEEEEIIIIOOOOOUUUUC';

    String resultado = texto;
    for (int i = 0; i < comAcento.length; i++) {
      resultado = resultado.replaceAll(comAcento[i], semAcento[i]);
    }
    return resultado.toLowerCase().trim();
  }

  /// Busca configuracao PEC do banco de dados
  /// Retorna dados da operadora configurada (URL, codAcesso, senha) + CNPJ da filial
  static Future<Map<String, dynamic>?> getConfiguracaoPec() async {
    try {
      final conn = await getConnection();
      if (conn == null) {
        debugPrint('[PEC Config] Conexao nula');
        return null;
      }

      // Buscar primeira empresa que tem operadoras_id configurado
      // Faz JOIN com operadoras para obter dados de conexao
      final results = await conn.query('''
        SELECT
          e.empresa_id,
          e.nome as empresa_nome,
          e.codempadm,
          o.operadoras_id,
          o.descricao as operadora_nome,
          o.pathwebservice,
          o.CODFORNECEDORADM,
          o.SENHAFORNECEDORADM
        FROM empresa e
        INNER JOIN operadoras o ON o.operadoras_id = e.operadoras_id
        WHERE e.apagado = 'N'
          AND e.operadoras_id IS NOT NULL
          AND e.operadoras_id > 0
        ORDER BY e.empresa_id
        LIMIT 1
      ''');

      if (results.isEmpty) {
        debugPrint('[PEC Config] Nenhuma empresa com PEC configurado');
        return null;
      }

      final row = results.first;
      var pathwebservice = row['pathwebservice']?.toString() ?? '';
      final codFornecedor = row['CODFORNECEDORADM']?.toString() ?? '';
      final senhaFornecedor = row['SENHAFORNECEDORADM']?.toString() ?? '';
      final operadoraNome = row['operadora_nome']?.toString() ?? '';
      final empresaNome = row['empresa_nome']?.toString() ?? '';
      final codEmpAdm = (row['codempadm'] as num?)?.toInt() ?? 0;
      // Credenciais LGPD - usar valores default (padrao do Tela de Vendas)
      const lgpdId = '0c3964a3-0c24-4d01-b380-bef035326744';
      const lgpdSenha = '220a4077-2f71-408c-be0e-8bd35cbba547';

      // Limpar URL (mesmo tratamento do Tela de Vendas)
      pathwebservice = pathwebservice.trim();
      pathwebservice = pathwebservice.replaceAll(r'\/', '/').replaceAll(r'\\', '/');
      if (pathwebservice.endsWith('/')) {
        pathwebservice = pathwebservice.substring(0, pathwebservice.length - 1);
      }
      // Forcar HTTPS (API redireciona HTTP para HTTPS)
      if (pathwebservice.startsWith('http://')) {
        pathwebservice = pathwebservice.replaceFirst('http://', 'https://');
      }

      debugPrint('[PEC Config] Encontrado: Empresa "$empresaNome", Operadora "$operadoraNome"');
      debugPrint('[PEC Config] URL: $pathwebservice');

      // Buscar CNPJ da filial (coluna cgc)
      String? cnpj;
      if (_filialId != null) {
        final cnpjResults = await conn.query('''
          SELECT cgc FROM filial WHERE filial_id = ? LIMIT 1
        ''', [_filialId]);

        if (cnpjResults.isNotEmpty) {
          final cnpjRaw = cnpjResults.first['cgc']?.toString() ?? '';
          cnpj = cnpjRaw.replaceAll(RegExp(r'[^0-9]'), '');
          debugPrint('[PEC Config] CNPJ filial: $cnpj');
        }
      }

      return {
        'urlEndpoint': pathwebservice,
        'codAcesso': codFornecedor,
        'senha': senhaFornecedor,
        'cnpj': cnpj ?? '',
        'operador': 'SISTEMABIG [3.41.0.0]', // Mesmo operador do Tela de Vendas
        'numBalconista': '1', // Deve ser >= 1 (PositiveInteger)
        'empresaId': codEmpAdm, // ID da empresa no PEC (codempadm)
        'lgpdId': lgpdId,
        'lgpdSenha': lgpdSenha,
        'nomeOperadora': operadoraNome, // Nome da operadora para exibicao
      };
    } catch (e) {
      debugPrint('[PEC Config] Erro ao buscar configuracao: $e');
      return null;
    }
  }

  /// Helper para obter conexao (uso interno)
  static Future<MySqlConnection?> _getConnection() async {
    return await getConnection();
  }
}
