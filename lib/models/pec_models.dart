/// Modelos para integacao com PEC (Programa de Economia Colaborativa)

/// Resposta generica do webservice PEC
class PecResponse<T> {
  final bool success;
  final int status;
  final String? mensagem;
  final T? data;

  PecResponse({
    required this.success,
    required this.status,
    this.mensagem,
    this.data,
  });

  factory PecResponse.success(T data) {
    return PecResponse(
      success: true,
      status: 0,
      data: data,
    );
  }

  factory PecResponse.error(String mensagem, {int status = 1}) {
    return PecResponse(
      success: false,
      status: status,
      mensagem: mensagem,
    );
  }
}

/// Resposta do metodo MAbrirTransacao
class TransacaoPec {
  final int status;
  final String transId;
  final String mensagem;
  final String? nomeCredenciado;
  final String? nomeConveniado;
  final bool programaDesconto;
  final bool fidelidade;

  TransacaoPec({
    required this.status,
    required this.transId,
    required this.mensagem,
    this.nomeCredenciado,
    this.nomeConveniado,
    this.programaDesconto = false,
    this.fidelidade = false,
  });

  factory TransacaoPec.fromXml(Map<String, String> map) {
    return TransacaoPec(
      status: int.tryParse(map['STATUS'] ?? '-1') ?? -1,
      transId: map['TRANSID'] ?? '',
      mensagem: map['MSG'] ?? '',
      nomeCredenciado: map['NOMECREDENCIADO'],
      nomeConveniado: map['NOMECONVENIADO'],
      programaDesconto: map['PROG_DESC'] == 'true',
      fidelidade: map['FIDELIDADE'] == 'true',
    );
  }

  bool get isSuccess => status == 0;
}

/// Produto para enviar na validacao MValidarProdutos
class ProdutoValidacaoPec {
  final String codBarras;
  final String descricao;
  final int quantidade;
  final int precoUnitarioBruto; // Em centavos (835 = R$ 8.35)
  final int precoFabrica; // Em centavos (599 = R$ 5.99)
  final int precoUnitarioLiquido; // Em centavos
  final int grupoId;
  final int origemDesconto; // 5 = PEC

  ProdutoValidacaoPec({
    required this.codBarras,
    required this.descricao,
    this.quantidade = 1,
    required this.precoUnitarioBruto,
    required this.precoFabrica,
    int? precoUnitarioLiquido,
    required this.grupoId,
    this.origemDesconto = 5,
  }) : precoUnitarioLiquido = precoUnitarioLiquido ?? precoUnitarioBruto;

  /// Gera XML do produto no formato exigido pelo webservice
  String toXml() {
    return '<PRODUTO>'
        '<CODBARRAS>$codBarras</CODBARRAS>'
        '<DESCRICAO>$descricao</DESCRICAO>'
        '<QTDE>$quantidade</QTDE>'
        '<PRCUNITBRU>$precoUnitarioBruto</PRCUNITBRU>'
        '<PRCFABRICA>$precoFabrica</PRCFABRICA>'
        '<PRCUNITLIQ>$precoUnitarioLiquido</PRCUNITLIQ>'
        '<GRUPO>$grupoId</GRUPO>'
        '<ORIGEM_DESCONTO>$origemDesconto</ORIGEM_DESCONTO>'
        '</PRODUTO>';
  }
}

/// Produto validado com desconto retornado pela API PEC
class ProdutoValidadoPec {
  final String codBarras;
  final int precoUnitario; // Em centavos
  final int percentualDesconto; // 550 = 5.50%
  final int valorDesconto; // Em centavos
  final int valorLiquido; // Em centavos (preco final para ofertas de jornal)
  final String nomePrograma; // Ex: "LISTA 8", "JORNAL"

  ProdutoValidadoPec({
    required this.codBarras,
    required this.precoUnitario,
    required this.percentualDesconto,
    required this.valorDesconto,
    required this.valorLiquido,
    required this.nomePrograma,
  });

  factory ProdutoValidadoPec.fromXml(Map<String, String> map) {
    return ProdutoValidadoPec(
      codBarras: map['CODBARRAS'] ?? '',
      precoUnitario: int.tryParse(map['PRCUNIT'] ?? '0') ?? 0,
      percentualDesconto: int.tryParse(map['PERCDESC'] ?? '0') ?? 0,
      valorDesconto: int.tryParse(map['VLRDESC'] ?? '0') ?? 0,
      valorLiquido: int.tryParse(map['VLRLIQ'] ?? '0') ?? 0,
      nomePrograma: map['NOMEPROGRAMA'] ?? '',
    );
  }

  /// Retorna o percentual de desconto formatado (ex: 5.50)
  double get descontoPercentual => percentualDesconto / 100;

  /// Retorna o preco unitario em reais
  double get precoUnitarioReais => precoUnitario / 100;

  /// Retorna o valor do desconto em reais
  double get valorDescontoReais => valorDesconto / 100;

  /// Retorna o valor liquido em reais (preco final para jornal)
  double get valorLiquidoReais => valorLiquido / 100;

  /// Verifica se tem desconto (por percentual OU valor liquido fixo)
  bool get temDesconto => percentualDesconto > 0 || valorLiquido > 0;

  /// Verifica se e oferta de jornal (preco fixo)
  bool get isOfertaJornal => valorLiquido > 0;
}

/// Resultado da consulta PEC para um produto
class ResultadoConsultaPec {
  final bool consultado;
  final bool temDesconto;
  final double descontoPercentual;
  final double valorDesconto;
  final double precoFinalPec;
  final String? nomePrograma;
  final bool isOfertaJornal;
  final String? erro;

  ResultadoConsultaPec({
    required this.consultado,
    required this.temDesconto,
    required this.descontoPercentual,
    required this.valorDesconto,
    required this.precoFinalPec,
    this.nomePrograma,
    this.isOfertaJornal = false,
    this.erro,
  });

  factory ResultadoConsultaPec.semDesconto() {
    return ResultadoConsultaPec(
      consultado: true,
      temDesconto: false,
      descontoPercentual: 0,
      valorDesconto: 0,
      precoFinalPec: 0,
    );
  }

  factory ResultadoConsultaPec.erro(String mensagem) {
    return ResultadoConsultaPec(
      consultado: false,
      temDesconto: false,
      descontoPercentual: 0,
      valorDesconto: 0,
      precoFinalPec: 0,
      erro: mensagem,
    );
  }

  factory ResultadoConsultaPec.naoConfigurado() {
    return ResultadoConsultaPec(
      consultado: false,
      temDesconto: false,
      descontoPercentual: 0,
      valorDesconto: 0,
      precoFinalPec: 0,
      erro: 'PEC nao configurado',
    );
  }
}

/// Configuracao do PEC
class ConfiguracaoPec {
  final String urlEndpoint;
  final String codAcesso;
  final String senha;
  final String cnpj;
  final String cartaoPecOuCpf; // Pode ser numero do cartao ou CPF
  final String operador;
  final int numBalconista;
  final int empresaId; // codempadm - ID da empresa no PEC
  final String lgpdId; // CLIENT_LGPD_ID
  final String lgpdSenha; // CLIENT_LGPD_SENHA

  // Numero do cartao real (preenchido apos consulta se for CPF)
  String? _cartaoNumero;

  ConfiguracaoPec({
    required this.urlEndpoint,
    required this.codAcesso,
    required this.senha,
    required this.cnpj,
    required String cartaoPec,
    this.operador = 'SISTEMABIG [3.41.0.0]',
    this.numBalconista = 1,
    this.empresaId = 0,
    this.lgpdId = '0c3964a3-0c24-4d01-b380-bef035326744',
    this.lgpdSenha = '220a4077-2f71-408c-be0e-8bd35cbba547',
  }) : cartaoPecOuCpf = cartaoPec;

  /// Retorna o numero do cartao (real ou o configurado se nao for CPF)
  String get cartaoPec => _cartaoNumero ?? cartaoPecOuCpf;

  /// Define o numero do cartao real (apos consulta por CPF)
  set cartaoNumero(String? valor) => _cartaoNumero = valor;

  /// Verifica se o valor configurado parece ser um CPF (11 digitos)
  bool get isCpf {
    final limpo = cartaoPecOuCpf.replaceAll(RegExp(r'[^0-9]'), '');
    return limpo.length == 11;
  }

  bool get isConfigurado =>
      urlEndpoint.isNotEmpty &&
      codAcesso.isNotEmpty &&
      senha.isNotEmpty &&
      cnpj.isNotEmpty &&
      cartaoPecOuCpf.isNotEmpty;

  /// XML com credenciais LGPD
  String get lgpdXml =>
      '<CLIENT_LGPD><CLIENT_LGPD_ID>$lgpdId</CLIENT_LGPD_ID><CLIENT_LGPD_SENHA>$lgpdSenha</CLIENT_LGPD_SENHA></CLIENT_LGPD>';

  Map<String, dynamic> toJson() => {
        'urlEndpoint': urlEndpoint,
        'codAcesso': codAcesso,
        'senha': senha,
        'cnpj': cnpj,
        'cartaoPec': cartaoPecOuCpf,
        'operador': operador,
        'numBalconista': numBalconista,
        'empresaId': empresaId,
        'lgpdId': lgpdId,
        'lgpdSenha': lgpdSenha,
      };

  factory ConfiguracaoPec.fromJson(Map<String, dynamic> json) {
    return ConfiguracaoPec(
      urlEndpoint: json['urlEndpoint'] ?? '',
      codAcesso: json['codAcesso'] ?? '',
      senha: json['senha'] ?? '',
      cnpj: json['cnpj'] ?? '',
      cartaoPec: json['cartaoPec'] ?? '',
      operador: json['operador'] ?? 'SISTEMABIG [3.41.0.0]',
      numBalconista: json['numBalconista'] ?? 1,
      empresaId: json['empresaId'] ?? 0,
      lgpdId: json['lgpdId'] ?? '0c3964a3-0c24-4d01-b380-bef035326744',
      lgpdSenha: json['lgpdSenha'] ?? '220a4077-2f71-408c-be0e-8bd35cbba547',
    );
  }
}
