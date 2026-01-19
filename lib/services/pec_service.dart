import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/pec_models.dart';

/// Servico para consulta de precos no PEC (Programa de Economia Colaborativa)
///
/// Este servico permite consultar descontos de produtos usando o cartao PEC.
/// A API usa protocolo SOAP com XML.
class PecService {
  final ConfiguracaoPec config;

  // Cache da transacao aberta
  String? _transIdAtual;
  DateTime? _transIdExpiracao;

  PecService(this.config);

  /// Credenciais XML para autenticacao
  String get _credenciaisXml =>
      '<CREDENCIADO><CODACESSO>${config.codAcesso}</CODACESSO><SENHA>${config.senha}</SENHA></CREDENCIADO>';

  /// URL do endpoint SOAP
  String get _soapEndpoint {
    String base = config.urlEndpoint;
    if (base.endsWith('/wpegaautor.asmx')) {
      base = base.substring(0, base.length - '/wpegaautor.asmx'.length);
    }
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/wsconvenio.asmx';
  }

  /// Verifica se o servico esta configurado
  bool get isConfigurado => config.isConfigurado;

  /// Executa uma requisicao SOAP
  Future<String> _executeRequest(String xmlBody, String metodo) async {
    final url = _soapEndpoint;

    try {
      final xmlInterno = '<?xml version="1.0" encoding="iso-8859-1"?>\n$xmlBody';
      final xmlEscaped = _escapeXml(xmlInterno);

      final soapEnvelope = '''<?xml version="1.0"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><SOAP-ENV:Body><$metodo xmlns="wsconvenio"><xml>$xmlEscaped
</xml></$metodo></SOAP-ENV:Body></SOAP-ENV:Envelope>''';

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction': 'wsconvenio/$metodo',
        },
        body: soapEnvelope,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return _extractSoapResponse(response.body);
      } else {
        throw Exception('Erro HTTP ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Erro na requisicao PEC: $e');
    }
  }

  String _escapeXml(String xml) {
    return xml
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _extractSoapResponse(String soapResponse) {
    final resultRegex =
        RegExp(r'<\w+Result[^>]*>(.*?)</\w+Result>', dotAll: true);
    final match = resultRegex.firstMatch(soapResponse);

    if (match != null) {
      String content = match.group(1) ?? '';
      content = content
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'");
      return content;
    }

    return soapResponse;
  }

  String _extractTag(String xml, String tagName) {
    final regex = RegExp('<$tagName>(.*?)</$tagName>', dotAll: true);
    final match = regex.firstMatch(xml);
    return match?.group(1)?.trim() ?? '';
  }

  Map<String, String> _extractFields(String xml) {
    final Map<String, String> result = {};
    final tagRegex = RegExp(r'<(\w+)>([^<>]*)</\1>');
    final matches = tagRegex.allMatches(xml);

    for (final match in matches) {
      final tagName = match.group(1) ?? '';
      final tagValue = match.group(2) ?? '';
      result[tagName] = tagValue.trim();
    }

    return result;
  }

  List<Map<String, String>> _extractList(
      String xml, String containerTag, String itemTag) {
    final List<Map<String, String>> result = [];

    final containerRegex =
        RegExp('<$containerTag>(.*?)</$containerTag>', dotAll: true);
    final containerMatch = containerRegex.firstMatch(xml);
    if (containerMatch == null) return result;

    final containerContent = containerMatch.group(1) ?? '';
    final itemRegex = RegExp('<$itemTag>(.*?)</$itemTag>', dotAll: true);
    final itemMatches = itemRegex.allMatches(containerContent);

    for (final itemMatch in itemMatches) {
      final itemContent = itemMatch.group(1) ?? '';
      final Map<String, String> item = {};

      final tagRegex = RegExp(r'<(\w+)>(.*?)</\1>', dotAll: true);
      final tagMatches = tagRegex.allMatches(itemContent);

      for (final tagMatch in tagMatches) {
        final tagName = tagMatch.group(1) ?? '';
        final tagValue = tagMatch.group(2) ?? '';
        item[tagName] = tagValue.trim();
      }

      if (item.isNotEmpty) {
        result.add(item);
      }
    }

    return result;
  }

  /// Abre uma transacao PEC
  Future<PecResponse<TransacaoPec>> _abrirTransacao({bool usarCpf = false}) async {
    // Se usarCpf=true, envia o CPF na tag CPF e deixa CARTAO vazio
    final cartaoTag = usarCpf ? '' : config.cartaoPec;
    final cpfTag = usarCpf ? config.cartaoPecOuCpf.replaceAll(RegExp(r'[^0-9]'), '') : '';

    final xmlBody = '<ABRIR_TRANSACAO_PARAM>'
        '<OPERADOR>${config.operador}</OPERADOR>'
        '$_credenciaisXml'
        '<CARTAO>$cartaoTag</CARTAO>'
        '<CPF>$cpfTag</CPF>'
        '<NUM_BALCONISTA>${config.numBalconista}</NUM_BALCONISTA>'
        '<CNPJ>${config.cnpj}</CNPJ>'
        '</ABRIR_TRANSACAO_PARAM>';

    debugPrint('[PEC] ========== ABRIR TRANSACAO ==========');
    debugPrint('[PEC] Modo: ${usarCpf ? "CPF direto" : "Numero do cartao"}');
    debugPrint('[PEC] URL Endpoint: ${config.urlEndpoint}');
    debugPrint('[PEC] SOAP Endpoint: $_soapEndpoint');
    debugPrint('[PEC] CARTAO: $cartaoTag');
    debugPrint('[PEC] CPF: $cpfTag');
    debugPrint('[PEC] CNPJ: ${config.cnpj}');
    debugPrint('[PEC] OPERADOR: ${config.operador}');
    debugPrint('[PEC] NUM_BALCONISTA: ${config.numBalconista}');
    debugPrint('[PEC] CODACESSO: ${config.codAcesso}');
    debugPrint('[PEC] SENHA: ${config.senha}');
    debugPrint('[PEC] XML Body: $xmlBody');

    try {
      final response = await _executeRequest(xmlBody, 'MAbrirTransacao');
      debugPrint('[PEC] Response: $response');
      final fields = _extractFields(response);
      final status = int.tryParse(fields['STATUS'] ?? '-1') ?? -1;

      debugPrint('[PEC] AbrirTransacao STATUS=$status, fields=$fields');

      if (status == 0) {
        final transacao = TransacaoPec.fromXml(fields);
        debugPrint('[PEC] Transacao aberta: ${transacao.transId}');
        return PecResponse.success(transacao);
      } else {
        final msg = fields['MSG'] ?? 'Erro ao abrir transacao';
        debugPrint('[PEC] Erro: $msg');
        return PecResponse.error(msg, status: status);
      }
    } catch (e) {
      debugPrint('[PEC] Exception: $e');
      return PecResponse.error('Erro: $e');
    }
  }

  /// Consulta cartao por CPF
  Future<String?> _consultarCartaoPorCpf(String cpf) async {
    final cpfLimpo = cpf.replaceAll(RegExp(r'[^0-9]'), '');
    if (cpfLimpo.length != 11) return null;

    final xmlBody = '<CONSULTAR_CARTOESV2_PARAM>'
        '<NOME_CARTAO>$cpfLimpo</NOME_CARTAO>'
        '<EMPRES_ID>${config.empresaId}</EMPRES_ID>'
        '$_credenciaisXml'
        '${config.lgpdXml}'
        '</CONSULTAR_CARTOESV2_PARAM>';

    debugPrint('[PEC] ========== CONSULTAR CARTAO POR CPF ==========');
    debugPrint('[PEC] CPF: $cpfLimpo');
    debugPrint('[PEC] EMPRES_ID: ${config.empresaId}');

    try {
      final response = await _executeRequest(xmlBody, 'MConsultarCartoesV2');
      debugPrint('[PEC] Response ConsultarCartoes: $response');

      final status = int.tryParse(_extractTag(response, 'STATUS')) ?? -1;
      debugPrint('[PEC] ConsultarCartoes STATUS=$status');

      if (status == 0) {
        final cartoes = _extractList(response, 'CARTOES', 'CARTAO');
        debugPrint('[PEC] Cartoes encontrados: ${cartoes.length}');

        if (cartoes.isNotEmpty) {
          // Busca cartao com CPF exato e liberado
          for (final cartao in cartoes) {
            debugPrint('[PEC] Campos do cartao: $cartao');
            final titularCpf = cartao['TITULAR_CPF'] ?? '';
            // Tenta diferentes tags para o numero do cartao (NUMPEC e NUM_CARTAO sao as mais comuns)
            final numPec = cartao['NUMPEC'] ?? cartao['NUM_PEC'] ?? cartao['NUM_CARTAO'] ?? cartao['NUMERO_CARTAO'] ?? '';
            final liberado = cartao['LIBERADO'] ?? cartao['SITUACAO'] ?? '';
            debugPrint('[PEC] Cartao: $numPec, CPF: $titularCpf, Liberado: $liberado');

            if (titularCpf == cpfLimpo && liberado == 'S' && numPec.isNotEmpty) {
              debugPrint('[PEC] Cartao encontrado para CPF: $numPec');
              return numPec;
            }
          }

          // Se nao encontrou exato, pega o primeiro liberado
          for (final cartao in cartoes) {
            final numPec = cartao['NUMPEC'] ?? cartao['NUM_PEC'] ?? cartao['NUM_CARTAO'] ?? cartao['NUMERO_CARTAO'] ?? '';
            final liberado = cartao['LIBERADO'] ?? cartao['SITUACAO'] ?? '';
            if (liberado == 'S' && numPec.isNotEmpty) {
              debugPrint('[PEC] Usando primeiro cartao liberado: $numPec');
              return numPec;
            }
          }

          // Ultimo recurso: primeiro cartao (mesmo sem LIBERADO=S)
          for (final cartao in cartoes) {
            final numPec = cartao['NUMPEC'] ?? cartao['NUM_PEC'] ?? cartao['NUM_CARTAO'] ?? cartao['NUMERO_CARTAO'] ?? '';
            if (numPec.isNotEmpty) {
              debugPrint('[PEC] Usando primeiro cartao disponivel (sem verificar liberado): $numPec');
              return numPec;
            }
          }
        }
      } else {
        final msg = _extractTag(response, 'MSG');
        debugPrint('[PEC] Erro ao consultar cartoes: $msg');
      }
    } catch (e) {
      debugPrint('[PEC] Exception ao consultar cartoes: $e');
    }

    return null;
  }

  /// Obtem uma transacao valida (abre nova se necessario)
  Future<String?> _obterTransacaoValida() async {
    // Verifica se tem transacao valida em cache (expira em 5 minutos)
    if (_transIdAtual != null && _transIdExpiracao != null) {
      if (DateTime.now().isBefore(_transIdExpiracao!)) {
        return _transIdAtual;
      }
    }

    // Se o valor configurado e um CPF, tenta primeiro abrir direto com CPF
    if (config.isCpf) {
      debugPrint('[PEC] Valor configurado e CPF, tentando abrir transacao com CPF direto...');

      // Primeira tentativa: usar CPF diretamente
      var result = await _abrirTransacao(usarCpf: true);
      if (result.success && result.data != null) {
        _transIdAtual = result.data!.transId;
        _transIdExpiracao = DateTime.now().add(const Duration(minutes: 5));
        debugPrint('[PEC] Transacao aberta com CPF direto!');
        return _transIdAtual;
      }

      debugPrint('[PEC] Falhou com CPF direto, tentando buscar numero do cartao...');

      // Segunda tentativa: buscar numero do cartao e usar ele
      final cartaoNumero = await _consultarCartaoPorCpf(config.cartaoPecOuCpf);
      if (cartaoNumero != null && cartaoNumero.isNotEmpty) {
        config.cartaoNumero = cartaoNumero;
        debugPrint('[PEC] Cartao encontrado: $cartaoNumero, tentando abrir transacao...');

        result = await _abrirTransacao(usarCpf: false);
        if (result.success && result.data != null) {
          _transIdAtual = result.data!.transId;
          _transIdExpiracao = DateTime.now().add(const Duration(minutes: 5));
          return _transIdAtual;
        }
      }

      debugPrint('[PEC] Nao foi possivel abrir transacao com CPF');
      return null;
    }

    // Se nao e CPF, abre transacao normalmente com numero do cartao
    final result = await _abrirTransacao(usarCpf: false);
    if (result.success && result.data != null) {
      _transIdAtual = result.data!.transId;
      _transIdExpiracao = DateTime.now().add(const Duration(minutes: 5));
      return _transIdAtual;
    }

    return null;
  }

  /// Consulta desconto PEC para um produto
  ///
  /// [codBarras] - Codigo de barras do produto (EAN)
  /// [descricao] - Descricao do produto
  /// [precoVenda] - Preco de venda em reais (ex: 8.35)
  /// [precoFabrica] - Preco de fabrica em reais (ex: 5.99)
  /// [grupoId] - ID do grupo do produto
  Future<ResultadoConsultaPec> consultarProduto({
    required String codBarras,
    required String descricao,
    required double precoVenda,
    required double precoFabrica,
    required int grupoId,
  }) async {
    if (!isConfigurado) {
      return ResultadoConsultaPec.naoConfigurado();
    }

    try {
      // Obter transacao valida
      final transId = await _obterTransacaoValida();
      if (transId == null) {
        return ResultadoConsultaPec.erro('Nao foi possivel abrir transacao PEC');
      }

      // Converter precos para centavos
      final precoVendaCentavos = (precoVenda * 100).round();
      final precoFabricaCentavos = (precoFabrica * 100).round();

      // Criar produto para validacao
      final produto = ProdutoValidacaoPec(
        codBarras: codBarras,
        descricao: descricao,
        precoUnitarioBruto: precoVendaCentavos,
        precoFabrica: precoFabricaCentavos,
        grupoId: grupoId,
      );

      // Montar XML de validacao (usa mesma logica da abertura de transacao)
      final cartaoTag = config.isCpf ? '' : config.cartaoPec;
      final cpfTag = config.isCpf ? config.cartaoPecOuCpf.replaceAll(RegExp(r'[^0-9]'), '') : '';

      final xmlBody = '<VALIDAR_PRODUTOS_PARAM>'
          '$_credenciaisXml'
          '<CARTAO>$cartaoTag</CARTAO>'
          '<CPF>$cpfTag</CPF>'
          '<TRANSID>$transId</TRANSID>'
          '<PRODUTOS>${produto.toXml()}</PRODUTOS>'
          '</VALIDAR_PRODUTOS_PARAM>';

      debugPrint('[PEC] Validando produto: $codBarras');
      debugPrint('[PEC] CARTAO: $cartaoTag, CPF: $cpfTag, TRANSID: $transId');

      final response = await _executeRequest(xmlBody, 'MValidarProdutos');
      final status = int.tryParse(_extractTag(response, 'STATUS')) ?? -1;

      debugPrint('[PEC] ValidarProdutos STATUS=$status');

      if (status == 0) {
        final produtosXml = _extractList(response, 'PRODUTOS', 'PRODUTO');

        if (produtosXml.isNotEmpty) {
          final produtoValidado = ProdutoValidadoPec.fromXml(produtosXml.first);

          debugPrint(
              '[PEC] Desconto: ${produtoValidado.descontoPercentual}%, Programa: ${produtoValidado.nomePrograma}');

          if (produtoValidado.temDesconto) {
            // Calcular preco final
            double precoFinal;
            bool isJornal = false;

            if (produtoValidado.valorLiquido > 0) {
              // Oferta de jornal - preco fixo
              precoFinal = produtoValidado.valorLiquidoReais;
              isJornal = true;
            } else {
              // Desconto percentual
              precoFinal =
                  precoVenda * (1 - produtoValidado.descontoPercentual / 100);
            }

            return ResultadoConsultaPec(
              consultado: true,
              temDesconto: true,
              descontoPercentual: produtoValidado.descontoPercentual,
              valorDesconto: produtoValidado.valorDescontoReais,
              precoFinalPec: precoFinal,
              nomePrograma: produtoValidado.nomePrograma,
              isOfertaJornal: isJornal,
            );
          }
        }

        return ResultadoConsultaPec.semDesconto();
      } else {
        final msg = _extractTag(response, 'MSG');
        return ResultadoConsultaPec.erro(msg.isNotEmpty ? msg : 'Erro na validacao');
      }
    } catch (e) {
      debugPrint('[PEC] Exception: $e');
      return ResultadoConsultaPec.erro('Erro: $e');
    }
  }

  /// Limpa cache de transacao (usar quando mudar cartao)
  void limparCache() {
    _transIdAtual = null;
    _transIdExpiracao = null;
  }
}
