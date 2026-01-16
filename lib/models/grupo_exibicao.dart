/// Tipo de filtro para o grupo de exibicao
enum TipoFiltroGrupo {
  grupo,        // Grupo de produtos
  especificacao, // Especificacao
  principioAtivo, // Principio ativo
}

/// Filtro de produtos para exibicao
enum FiltroEstoqueDesconto {
  todos,           // Todos os produtos
  somenteEstoque,  // Somente com estoque
  somenteDesconto, // Somente com desconto
  estoqueEDesconto, // Com estoque E com desconto
}

/// Representa um grupo de exibicao de promocoes
class GrupoExibicao {
  final String id;
  final String nome;
  final TipoFiltroGrupo tipo;
  final List<int> idsItens; // IDs dos grupos/especificacoes/principios ativos
  final List<String> nomesItens; // Nomes para exibicao
  final FiltroEstoqueDesconto filtro;
  final bool ativo;
  final DateTime? criadoEm;

  GrupoExibicao({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.idsItens,
    required this.nomesItens,
    required this.filtro,
    this.ativo = true,
    this.criadoEm,
  });

  /// Descricao do tipo de filtro
  String get tipoDescricao {
    switch (tipo) {
      case TipoFiltroGrupo.grupo:
        return 'Grupo de Produtos';
      case TipoFiltroGrupo.especificacao:
        return 'Especificacao';
      case TipoFiltroGrupo.principioAtivo:
        return 'Principio Ativo';
    }
  }

  /// Descricao do filtro de estoque/desconto
  String get filtroDescricao {
    switch (filtro) {
      case FiltroEstoqueDesconto.todos:
        return 'Todos os produtos';
      case FiltroEstoqueDesconto.somenteEstoque:
        return 'Somente com estoque';
      case FiltroEstoqueDesconto.somenteDesconto:
        return 'Somente com desconto';
      case FiltroEstoqueDesconto.estoqueEDesconto:
        return 'Com estoque e desconto';
    }
  }

  /// Converte para Map para persistencia
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'tipo': tipo.index,
      'idsItens': idsItens,
      'nomesItens': nomesItens,
      'filtro': filtro.index,
      'ativo': ativo,
      'criadoEm': criadoEm?.toIso8601String(),
    };
  }

  /// Cria a partir de Map
  factory GrupoExibicao.fromMap(Map<String, dynamic> map) {
    return GrupoExibicao(
      id: map['id'] as String,
      nome: map['nome'] as String,
      tipo: TipoFiltroGrupo.values[map['tipo'] as int],
      idsItens: (map['idsItens'] as List).map((e) => e as int).toList(),
      nomesItens: (map['nomesItens'] as List).map((e) => e as String).toList(),
      filtro: FiltroEstoqueDesconto.values[map['filtro'] as int],
      ativo: map['ativo'] as bool? ?? true,
      criadoEm: map['criadoEm'] != null ? DateTime.tryParse(map['criadoEm'] as String) : null,
    );
  }

  /// Cria copia com alteracoes
  GrupoExibicao copyWith({
    String? id,
    String? nome,
    TipoFiltroGrupo? tipo,
    List<int>? idsItens,
    List<String>? nomesItens,
    FiltroEstoqueDesconto? filtro,
    bool? ativo,
    DateTime? criadoEm,
  }) {
    return GrupoExibicao(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      tipo: tipo ?? this.tipo,
      idsItens: idsItens ?? this.idsItens,
      nomesItens: nomesItens ?? this.nomesItens,
      filtro: filtro ?? this.filtro,
      ativo: ativo ?? this.ativo,
      criadoEm: criadoEm ?? this.criadoEm,
    );
  }
}
