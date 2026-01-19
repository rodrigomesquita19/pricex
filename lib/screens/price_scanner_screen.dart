import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/grupo_exibicao.dart';
import '../models/pec_models.dart';
import '../services/beep_service.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';
import '../services/pec_service.dart';
import 'config_screen.dart';

class PriceScannerScreen extends StatefulWidget {
  const PriceScannerScreen({super.key});

  @override
  State<PriceScannerScreen> createState() => _PriceScannerScreenState();
}

class _PriceScannerScreenState extends State<PriceScannerScreen>
    with SingleTickerProviderStateMixin {
  // Controlador da camera
  MobileScannerController? _scannerController;
  bool _cameraAtiva = false;
  bool _processandoLeitura = false;

  // Zoom da camera
  double _zoomLevel = 0.0;

  // Timer para limpar produto da tela (60 segundos)
  Timer? _productDisplayTimer;
  static const Duration _productDisplayTimeout = Duration(seconds: 60);

  // Dados do produto atual
  Map<String, dynamic>? _produtoAtual;
  bool _carregandoProduto = false;
  String? _mensagemErro;

  // Mensagem de leitura de codigo
  bool _lendoCodigo = false;

  // Modo de busca (true = camera, false = pesquisa por nome)
  bool _modoBuscaCamera = true;

  // Animacao pulsante para botao de pesquisa
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Pesquisa
  final _pesquisaController = TextEditingController();
  final _pesquisaFocusNode = FocusNode();
  List<Map<String, dynamic>> _resultadosPesquisa = [];
  bool _pesquisando = false;
  Timer? _debounceTimer;
  static const int _minCaracteresParaPesquisa = 2;
  static const Duration _debounceDelay = Duration(milliseconds: 400);

  // Timer de inatividade da pesquisa (30 segundos para voltar para camera)
  Timer? _pesquisaInactivityTimer;
  static const Duration _pesquisaInactivityTimeout = Duration(seconds: 30);

  // Reconhecimento de voz
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechDisponivel = false;
  bool _ouvindo = false;

  // Tabela de desconto
  int _tabelaDescontoId = 1;

  // Formatador de moeda
  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  // Carrossel de promocoes (ticker na parte inferior)
  List<Map<String, dynamic>> _produtosCarrossel = [];
  ScrollController? _carrosselScrollController;
  Timer? _carrosselTimer;
  Timer? _carrosselRefreshTimer;
  bool _carrosselAtivo = false;
  bool _combosCarrosselAtivo = true; // Exibir combos no carrossel
  double _velocidadeCarrossel = 1.0; // Incremento de pixels por frame
  static const Duration _carrosselRefreshInterval = Duration(seconds: 60);

  // PEC (Programa de Economia Colaborativa)
  PecService? _pecService;
  bool _pecAtivo = false;
  ResultadoConsultaPec? _resultadoPec;
  bool _consultandoPec = false;
  String _nomeOperadoraPec = 'PEC'; // Nome da operadora para exibicao

  // Logo da loja
  String? _logoLojaPath;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _inicializarReconhecimentoVoz();
    _inicializarCarrossel();
    // Adicionar listener para pesquisa automatica
    _pesquisaController.addListener(_onSearchChanged);

    // Inicializar animacao pulsante
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  /// Inicializa o carrossel de promocoes
  Future<void> _inicializarCarrossel() async {
    debugPrint('[Carrossel] Inicializando carrossel...');
    _carrosselScrollController = ScrollController();
    // Carregar velocidade configurada
    final nivelVelocidade = await ConfigService.getVelocidadeCarrossel();
    _velocidadeCarrossel = ConfigService.getIncrementoVelocidade(nivelVelocidade);
    // Carregar config de combos
    _combosCarrosselAtivo = await ConfigService.isCombosCarrosselAtivo();
    debugPrint('[Carrossel] Velocidade: ${ConfigService.getNomeVelocidade(nivelVelocidade)} (incremento: $_velocidadeCarrossel)');
    debugPrint('[Carrossel] Combos ativo: $_combosCarrosselAtivo');
    await _carregarProdutosCarrossel();
    _iniciarAnimacaoCarrossel();
    _iniciarRefreshCarrossel();
    debugPrint('[Carrossel] Inicializacao concluida. Produtos: ${_produtosCarrossel.length}');
  }

  // Produtos pendentes para atualizar (carregados em background)
  List<Map<String, dynamic>>? _produtosCarrosselPendentes;

  /// Inicia o timer de atualizacao automatica do carrossel (a cada 60 segundos)
  void _iniciarRefreshCarrossel() {
    _carrosselRefreshTimer?.cancel();
    _carrosselRefreshTimer = Timer.periodic(_carrosselRefreshInterval, (_) async {
      if (mounted && _carrosselAtivo) {
        debugPrint('[Carrossel] Carregando produtos em background...');
        await _carregarProdutosCarrosselBackground();
      }
    });
  }

  /// Carrega produtos em background sem atualizar a UI imediatamente
  Future<void> _carregarProdutosCarrosselBackground() async {
    try {
      // Verificar se carrossel esta ativo
      final ativo = await ConfigService.isCarrosselAtivo();
      if (!ativo) return;

      // Buscar grupos de exibicao ativos
      final grupos = await ConfigService.getGruposExibicao();
      final gruposAtivos = grupos.where((g) => g.ativo).toList();
      if (gruposAtivos.isEmpty) return;

      List<Map<String, dynamic>> novosProdutos = [];

      for (final grupo in gruposAtivos) {
        String tipoFiltro;
        switch (grupo.tipo) {
          case TipoFiltroGrupo.grupo:
            tipoFiltro = 'grupo';
            break;
          case TipoFiltroGrupo.especificacao:
            tipoFiltro = 'especificacao';
            break;
          case TipoFiltroGrupo.principioAtivo:
            tipoFiltro = 'principio_ativo';
            break;
        }

        String filtroEstoque;
        switch (grupo.filtro) {
          case FiltroEstoqueDesconto.todos:
            filtroEstoque = 'todos';
            break;
          case FiltroEstoqueDesconto.comDesconto:
            filtroEstoque = 'desconto';
            break;
          case FiltroEstoqueDesconto.descontoEEstoque:
            filtroEstoque = 'estoque_desconto';
            break;
        }

        final produtos = await DatabaseService.buscarProdutosParaCarrossel(
          tipoFiltro: tipoFiltro,
          ids: grupo.idsItens,
          filtroEstoqueDesconto: filtroEstoque,
          tabelaDescontoId: _tabelaDescontoId,
          limite: 20,
        );
        novosProdutos.addAll(produtos);
      }

      // Buscar combos ativos se configurado
      if (_combosCarrosselAtivo) {
        final temFiltroEstoque = gruposAtivos.any(
          (g) => g.filtro == FiltroEstoqueDesconto.descontoEEstoque
        );
        final combos = await DatabaseService.buscarCombosParaCarrossel(
          somenteComEstoque: temFiltroEstoque,
        );
        novosProdutos.addAll(combos);
      }

      novosProdutos.shuffle();

      // Armazenar para aplicar quando for seguro
      _produtosCarrosselPendentes = novosProdutos;
      debugPrint('[Carrossel] ${novosProdutos.length} itens carregados em background, aguardando momento seguro...');
    } catch (e) {
      debugPrint('[Carrossel] Erro ao carregar em background: $e');
    }
  }

  /// Aplica os produtos pendentes (chamado quando scroll esta no inicio)
  void _aplicarProdutosPendentes() {
    if (_produtosCarrosselPendentes != null && mounted) {
      setState(() {
        _produtosCarrossel = _produtosCarrosselPendentes!;
      });
      debugPrint('[Carrossel] Produtos atualizados suavemente. Total: ${_produtosCarrossel.length}');
      _produtosCarrosselPendentes = null;
    }
  }

  /// Carrega os produtos para o carrossel baseado nos grupos configurados
  Future<void> _carregarProdutosCarrossel() async {
    try {
      debugPrint('[Carrossel] Iniciando carregamento de produtos...');

      // Verificar se carrossel esta ativo
      _carrosselAtivo = await ConfigService.isCarrosselAtivo();
      debugPrint('[Carrossel] Carrossel ativo: $_carrosselAtivo');
      if (!_carrosselAtivo) {
        debugPrint('[Carrossel] Carrossel DESATIVADO nas configuracoes. Abortando.');
        return;
      }

      // Buscar grupos de exibicao ativos
      final grupos = await ConfigService.getGruposExibicao();
      debugPrint('[Carrossel] Total de grupos configurados: ${grupos.length}');
      final gruposAtivos = grupos.where((g) => g.ativo).toList();
      debugPrint('[Carrossel] Grupos ativos: ${gruposAtivos.length}');

      if (gruposAtivos.isEmpty) {
        debugPrint('[Carrossel] Nenhum grupo ativo encontrado. Abortando.');
        return;
      }

      List<Map<String, dynamic>> todosProdutos = [];

      // Buscar produtos de cada grupo
      for (final grupo in gruposAtivos) {
        debugPrint('[Carrossel] Processando grupo: ${grupo.nome} (${grupo.tipo})');
        debugPrint('[Carrossel]   IDs: ${grupo.idsItens}');

        // Converter enum para string do banco
        String tipoFiltro;
        switch (grupo.tipo) {
          case TipoFiltroGrupo.grupo:
            tipoFiltro = 'grupo';
            break;
          case TipoFiltroGrupo.especificacao:
            tipoFiltro = 'especificacao';
            break;
          case TipoFiltroGrupo.principioAtivo:
            tipoFiltro = 'principio_ativo';
            break;
        }

        String filtroEstoque;
        switch (grupo.filtro) {
          case FiltroEstoqueDesconto.todos:
            filtroEstoque = 'todos';
            break;
          case FiltroEstoqueDesconto.comDesconto:
            filtroEstoque = 'desconto';
            break;
          case FiltroEstoqueDesconto.descontoEEstoque:
            filtroEstoque = 'estoque_desconto';
            break;
        }

        debugPrint('[Carrossel]   tipoFiltro: $tipoFiltro, filtroEstoque: $filtroEstoque');

        final produtos = await DatabaseService.buscarProdutosParaCarrossel(
          tipoFiltro: tipoFiltro,
          ids: grupo.idsItens,
          filtroEstoqueDesconto: filtroEstoque,
          tabelaDescontoId: _tabelaDescontoId,
          limite: 20,
        );
        debugPrint('[Carrossel]   Produtos encontrados: ${produtos.length}');
        todosProdutos.addAll(produtos);
      }

      // Buscar combos ativos se configurado
      if (_combosCarrosselAtivo) {
        debugPrint('[Carrossel] Buscando combos ativos...');
        // Verificar se algum grupo tem filtro de estoque
        final temFiltroEstoque = gruposAtivos.any(
          (g) => g.filtro == FiltroEstoqueDesconto.descontoEEstoque
        );
        final combos = await DatabaseService.buscarCombosParaCarrossel(
          somenteComEstoque: temFiltroEstoque,
        );
        debugPrint('[Carrossel] Combos encontrados: ${combos.length}');
        todosProdutos.addAll(combos);
      }

      // Embaralhar para exibicao aleatoria
      todosProdutos.shuffle();

      debugPrint('[Carrossel] TOTAL de itens carregados (produtos + combos): ${todosProdutos.length}');

      if (mounted) {
        setState(() {
          _produtosCarrossel = todosProdutos;
        });
        debugPrint('[Carrossel] setState chamado. _produtosCarrossel.length = ${_produtosCarrossel.length}');
      }
    } catch (e, stackTrace) {
      debugPrint('[Carrossel] ERRO ao carregar produtos: $e');
      debugPrint('[Carrossel] StackTrace: $stackTrace');
    }
  }

  /// Inicia a animacao do carrossel (scroll automatico)
  void _iniciarAnimacaoCarrossel() {
    _carrosselTimer?.cancel();

    debugPrint('[Carrossel] Tentando iniciar animacao. Produtos: ${_produtosCarrossel.length}');

    if (_produtosCarrossel.isEmpty) {
      debugPrint('[Carrossel] Lista vazia, animacao NAO iniciada.');
      return;
    }

    debugPrint('[Carrossel] Iniciando timer de animacao...');
    _carrosselTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_carrosselScrollController != null &&
          _carrosselScrollController!.hasClients &&
          mounted) {
        final maxScroll = _carrosselScrollController!.position.maxScrollExtent;
        final currentScroll = _carrosselScrollController!.offset;

        if (currentScroll >= maxScroll) {
          // Voltar ao inicio - momento seguro para atualizar produtos
          _carrosselScrollController!.jumpTo(0);
          // Aplicar produtos pendentes se houver
          if (_produtosCarrosselPendentes != null) {
            _aplicarProdutosPendentes();
          }
        } else {
          // Scroll suave com velocidade configurada
          _carrosselScrollController!.jumpTo(currentScroll + _velocidadeCarrossel);
        }
      }
    });
  }

  Future<void> _carregarConfiguracoes() async {
    _tabelaDescontoId = await ConfigService.getTabelaDescontoId();

    // Carregar configuracao PEC
    _pecAtivo = await ConfigService.isPecAtivo();
    if (_pecAtivo) {
      final cartaoPec = await ConfigService.getCartaoPec();
      if (cartaoPec != null && cartaoPec.isNotEmpty) {
        // Buscar configuracao PEC do banco de dados (operadoras)
        final pecConfigDb = await DatabaseService.getConfiguracaoPec();
        if (pecConfigDb != null) {
          final urlEndpoint = pecConfigDb['urlEndpoint'] as String? ?? '';
          final codAcesso = pecConfigDb['codAcesso'] as String? ?? '';
          final senha = pecConfigDb['senha'] as String? ?? '';
          final cnpj = pecConfigDb['cnpj'] as String? ?? '';
          final operador = pecConfigDb['operador'] as String? ?? 'SISTEMABIG [3.41.0.0]';
          final numBalconistaStr = pecConfigDb['numBalconista'] as String? ?? '1';
          final numBalconista = int.tryParse(numBalconistaStr) ?? 1;
          final empresaId = pecConfigDb['empresaId'] as int? ?? 0;
          final lgpdId = pecConfigDb['lgpdId'] as String? ?? '';
          final lgpdSenha = pecConfigDb['lgpdSenha'] as String? ?? '';
          final nomeOperadora = pecConfigDb['nomeOperadora'] as String? ?? 'PEC';

          if (urlEndpoint.isNotEmpty && codAcesso.isNotEmpty) {
            final pecConfig = ConfiguracaoPec(
              urlEndpoint: urlEndpoint,
              codAcesso: codAcesso,
              senha: senha,
              cnpj: cnpj,
              cartaoPec: cartaoPec,
              operador: operador,
              numBalconista: numBalconista,
              empresaId: empresaId,
              lgpdId: lgpdId,
              lgpdSenha: lgpdSenha,
            );
            _pecService = PecService(pecConfig);
            _nomeOperadoraPec = nomeOperadora.isNotEmpty ? nomeOperadora : 'PEC';
            debugPrint('[PEC] Servico PEC inicializado. Operadora: $_nomeOperadoraPec, Cartao/CPF: $cartaoPec, CNPJ: $cnpj');
            debugPrint('[PEC] URL: $urlEndpoint');
          } else {
            debugPrint('[PEC] Configuracao PEC incompleta no banco, PEC desativado');
            _pecAtivo = false;
          }
        } else {
          debugPrint('[PEC] Nenhuma operadora PEC configurada no banco, PEC desativado');
          _pecAtivo = false;
        }
      } else {
        debugPrint('[PEC] Cartao PEC nao configurado, PEC desativado');
        _pecAtivo = false;
      }
    }

    // Carregar logo da loja
    _logoLojaPath = await ConfigService.getLogoLoja();
    if (_logoLojaPath != null && !File(_logoLojaPath!).existsSync()) {
      _logoLojaPath = null; // Limpar se o arquivo nao existe mais
    }

    // Verificar se tem configuracao
    final hasConfig = await ConfigService.hasConfig();
    if (!hasConfig && mounted) {
      _abrirConfiguracoes();
    } else if (mounted && _modoBuscaCamera) {
      // Ativar camera automaticamente no modo camera
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _modoBuscaCamera && !_cameraAtiva) {
          _ativarCamera();
        }
      });
    }
  }

  /// Inicializa o reconhecimento de voz
  Future<void> _inicializarReconhecimentoVoz() async {
    _speechDisponivel = await _speech.initialize(
      onStatus: (status) {
        debugPrint('[Speech] Status: $status');
        if (status == 'done' || status == 'notListening') {
          if (mounted) {
            setState(() => _ouvindo = false);
            // Reiniciar automaticamente se ainda estiver no modo de busca por nome
            if (!_modoBuscaCamera && _speechDisponivel) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted && !_modoBuscaCamera && !_ouvindo) {
                  _iniciarReconhecimentoVozContinuo();
                }
              });
            }
          }
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _ouvindo = false);
          // Tentar reiniciar apos erro se ainda estiver no modo de busca
          if (!_modoBuscaCamera && _speechDisponivel) {
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted && !_modoBuscaCamera && !_ouvindo) {
                _iniciarReconhecimentoVozContinuo();
              }
            });
          }
        }
        debugPrint('[Speech] Erro: $error');
      },
    );
    if (mounted) {
      setState(() {});
    }
  }

  /// Inicia o reconhecimento de voz em modo continuo (para busca por nome)
  Future<void> _iniciarReconhecimentoVozContinuo() async {
    if (!_speechDisponivel || _ouvindo || _modoBuscaCamera) return;

    setState(() => _ouvindo = true);

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final texto = result.recognizedWords;
          if (texto.isNotEmpty) {
            _pesquisaController.text = texto;
            _pesquisaController.selection = TextSelection.fromPosition(
              TextPosition(offset: _pesquisaController.text.length),
            );
          }
        }
      },
      localeId: 'pt_BR',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.search,
        cancelOnError: false,
        partialResults: true,
      ),
    );
  }

  /// Inicia/para o reconhecimento de voz
  Future<void> _toggleReconhecimentoVoz() async {
    if (!_speechDisponivel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reconhecimento de voz não disponível'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_ouvindo) {
      await _pararReconhecimentoVoz();
    } else {
      await _iniciarReconhecimentoVozContinuo();
    }
  }

  void _abrirConfiguracoes() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfigScreen()),
    );

    if (result == true) {
      _tabelaDescontoId = await ConfigService.getTabelaDescontoId();
    }

    // Sempre recarregar configuracoes do carrossel e logo ao voltar
    final nivelVelocidade = await ConfigService.getVelocidadeCarrossel();
    final novaVelocidade = ConfigService.getIncrementoVelocidade(nivelVelocidade);
    if (novaVelocidade != _velocidadeCarrossel) {
      debugPrint('[Carrossel] Velocidade atualizada: ${ConfigService.getNomeVelocidade(nivelVelocidade)} (incremento: $novaVelocidade)');
      _velocidadeCarrossel = novaVelocidade;
    }

    // Recarregar config de combos
    final novoCombosAtivo = await ConfigService.isCombosCarrosselAtivo();
    if (novoCombosAtivo != _combosCarrosselAtivo) {
      debugPrint('[Carrossel] Combos atualizado: $novoCombosAtivo');
      _combosCarrosselAtivo = novoCombosAtivo;
    }

    // Recarregar logo da loja
    final novoLogoPath = await ConfigService.getLogoLoja();
    if (novoLogoPath != _logoLojaPath) {
      setState(() {
        _logoLojaPath = (novoLogoPath != null && File(novoLogoPath).existsSync())
            ? novoLogoPath
            : null;
      });
    }
  }

  void _ativarCamera() {
    if (_cameraAtiva) return;

    setState(() {
      _cameraAtiva = true;
      _zoomLevel = 0.7; // Zoom inicial de 70%
    });

    _scannerController = MobileScannerController(
      facing: CameraFacing.front,
      detectionSpeed: DetectionSpeed.normal,
    );

    // Aplicar zoom inicial apos a camera inicializar (multiplas tentativas)
    _aplicarZoomInicial();
  }

  /// Aplica o zoom inicial com retry para garantir que a camera esta pronta
  void _aplicarZoomInicial() async {
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (_scannerController != null && mounted) {
        try {
          await _scannerController!.setZoomScale(0.7);
          break; // Sucesso, sair do loop
        } catch (e) {
          // Camera ainda nao pronta, tentar novamente
        }
      }
    }
  }

  void _desativarCamera() {
    _scannerController?.dispose();
    _scannerController = null;

    setState(() {
      _cameraAtiva = false;
    });
  }

  void _setZoom(double value) {
    setState(() {
      _zoomLevel = value;
    });
    _scannerController?.setZoomScale(value);
  }

  /// Inicia o timer de exibicao do produto (60 segundos)
  void _iniciarTimerProduto() {
    _productDisplayTimer?.cancel();

    _productDisplayTimer = Timer(_productDisplayTimeout, () {
      if (mounted) {
        setState(() {
          _produtoAtual = null;
          _mensagemErro = null;
        });
      }
    });
  }


  void _onBarcodeDetect(BarcodeCapture capture) async {
    if (_processandoLeitura) return;
    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.first;
    final code = barcode.rawValue;
    if (code == null || code.isEmpty) return;

    // Marcar como processando e mostrar mensagem de leitura
    setState(() {
      _processandoLeitura = true;
      _lendoCodigo = true;
      _mensagemErro = null;
    });

    // Tocar BIP de leitura imediatamente
    BeepService.playSuccess();

    // Aguardar um momento para mostrar a mensagem de "Lendo codigo de barras"
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    // Agora buscar o produto
    setState(() {
      _lendoCodigo = false;
      _carregandoProduto = true;
    });

    // Buscar produto
    final resultado = await DatabaseService.buscarProdutoPorCodigoBarras(
      code,
      tabelaDescontoId: _tabelaDescontoId,
    );

    if (!mounted) return;

    // Limpar resultado PEC anterior
    _resultadoPec = null;

    setState(() {
      _carregandoProduto = false;

      if (resultado['sucesso'] == true) {
        _produtoAtual = resultado;
        _mensagemErro = null;
      } else {
        _produtoAtual = null;
        _mensagemErro = resultado['erro'] ?? 'Erro ao buscar produto';
      }
    });

    // Consultar PEC se produto encontrado e PEC ativo
    if (resultado['sucesso'] == true && _pecAtivo && _pecService != null) {
      _consultarPec(resultado);
    }

    // Iniciar timer de 60 segundos para limpar o produto da tela
    if (resultado['sucesso'] == true) {
      _iniciarTimerProduto();
    }

    // Aguardar 2.5 segundos antes de permitir nova leitura (interativo)
    await Future.delayed(const Duration(milliseconds: 2500));

    if (mounted) {
      setState(() {
        _processandoLeitura = false;
      });
    }
  }

  // ========== PEC ==========

  /// Consulta desconto PEC para o produto
  Future<void> _consultarPec(Map<String, dynamic> produto) async {
    if (_pecService == null || !_pecAtivo) return;

    final barras = produto['barras']?.toString() ?? '';
    final descricao = produto['descricao']?.toString() ?? '';
    final precoCheio = (produto['precoCheio'] as num?)?.toDouble() ?? 0;
    final precoFabrica = (produto['precoFabrica'] as num?)?.toDouble() ?? precoCheio * 0.7;
    final grupoId = (produto['grupoId'] as num?)?.toInt() ?? 0;

    if (barras.isEmpty || precoCheio <= 0) return;

    setState(() => _consultandoPec = true);

    try {
      debugPrint('[PEC] Consultando produto: $barras');

      final resultado = await _pecService!.consultarProduto(
        codBarras: barras,
        descricao: descricao,
        precoVenda: precoCheio,
        precoFabrica: precoFabrica,
        grupoId: grupoId,
      );

      if (mounted) {
        setState(() {
          _resultadoPec = resultado;
          _consultandoPec = false;
        });

        if (resultado.temDesconto) {
          debugPrint('[PEC] Desconto encontrado: ${resultado.descontoPercentual}% - ${resultado.nomePrograma}');
        } else if (resultado.consultado) {
          debugPrint('[PEC] Produto consultado, sem desconto');
        } else {
          debugPrint('[PEC] Erro na consulta: ${resultado.erro}');
        }
      }
    } catch (e) {
      debugPrint('[PEC] Erro: $e');
      if (mounted) {
        setState(() {
          _resultadoPec = ResultadoConsultaPec.erro(e.toString());
          _consultandoPec = false;
        });
      }
    }
  }

  // ========== PESQUISA ==========

  /// Alterna entre modo camera e modo pesquisa
  void _alternarModoBusca() {
    setState(() {
      _modoBuscaCamera = !_modoBuscaCamera;

      if (_modoBuscaCamera) {
        // Voltando para modo camera - parar reconhecimento de voz
        _pesquisaController.clear();
        _resultadosPesquisa = [];
        _cancelarTimerPesquisa();
        _pararReconhecimentoVoz();
        _ativarCamera();
      } else {
        // Entrando no modo pesquisa
        _desativarCamera();
        _iniciarTimerPesquisa();
        // Iniciar pesquisa por voz automaticamente (modo continuo)
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_modoBuscaCamera && _speechDisponivel && !_ouvindo) {
            _iniciarReconhecimentoVozContinuo();
          }
        });
      }
    });
  }

  /// Para o reconhecimento de voz
  Future<void> _pararReconhecimentoVoz() async {
    if (_ouvindo) {
      await _speech.stop();
      setState(() => _ouvindo = false);
    }
  }

  /// Inicia o timer de inatividade da pesquisa
  void _iniciarTimerPesquisa() {
    _cancelarTimerPesquisa();
    _pesquisaInactivityTimer = Timer(_pesquisaInactivityTimeout, () {
      if (mounted && !_modoBuscaCamera) {
        // Voltar para modo camera apos inatividade
        _alternarModoBusca();
      }
    });
  }

  /// Cancela o timer de inatividade da pesquisa
  void _cancelarTimerPesquisa() {
    _pesquisaInactivityTimer?.cancel();
    _pesquisaInactivityTimer = null;
  }

  /// Reinicia o timer de pesquisa (chamado ao tocar na tela)
  void _reiniciarTimerPesquisa() {
    if (!_modoBuscaCamera) {
      _iniciarTimerPesquisa();
    }
  }

  /// Listener acionado pelo teclado no campo de pesquisa
  void _onSearchChanged() {
    _debounceTimer?.cancel();

    final termo = _pesquisaController.text.trim();

    // Limpar resultados se o campo estiver vazio
    if (termo.isEmpty) {
      setState(() {
        _resultadosPesquisa = [];
        _mensagemErro = null;
      });
      return;
    }

    // So disparar pesquisa automatica se atingir o minimo de caracteres
    if (termo.length >= _minCaracteresParaPesquisa) {
      _debounceTimer = Timer(_debounceDelay, () {
        _executarPesquisa();
      });
    }
  }

  /// Executa a pesquisa apos debounce ou ao pressionar Enter
  Future<void> _executarPesquisa() async {
    final termo = _pesquisaController.text.trim();

    if (termo.isEmpty) {
      setState(() {
        _resultadosPesquisa = [];
        _mensagemErro = null;
      });
      return;
    }

    setState(() => _pesquisando = true);

    try {
      final resultados = await DatabaseService.pesquisarProdutos(
        termo,
        tabelaDescontoId: _tabelaDescontoId,
      );

      if (mounted) {
        setState(() {
          _resultadosPesquisa = resultados;
          _pesquisando = false;
          if (resultados.isEmpty) {
            _mensagemErro = 'Nenhum produto encontrado';
          } else {
            _mensagemErro = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pesquisando = false;
          _mensagemErro = 'Erro ao pesquisar: $e';
        });
      }
    }
  }

  /// Seleciona um produto da pesquisa e busca detalhes completos
  Future<void> _selecionarProduto(Map<String, dynamic> produto) async {
    setState(() {
      _modoBuscaCamera = true;
      _pesquisaController.clear();
      _resultadosPesquisa = [];
      _carregandoProduto = true;
    });

    // Buscar detalhes completos do produto (incluindo regras de desconto, combos, etc.)
    final barras = produto['barras']?.toString() ?? '';
    if (barras.isNotEmpty) {
      final detalhes = await DatabaseService.buscarProdutoPorCodigoBarras(
        barras,
        tabelaDescontoId: _tabelaDescontoId,
      );

      if (mounted) {
        setState(() {
          _produtoAtual = detalhes;
          _carregandoProduto = false;
        });

        // Consultar PEC se produto encontrado e PEC ativo
        if (detalhes['sucesso'] == true && _pecAtivo && _pecService != null) {
          _consultarPec(detalhes);
        }

        // Iniciar timer de 60 segundos para limpar o produto da tela
        _iniciarTimerProduto();
      }
    } else {
      // Fallback para dados basicos se nao tiver barras
      final detalhesBasicos = {
        'sucesso': true,
        ...produto,
      };
      setState(() {
        _produtoAtual = detalhesBasicos;
        _carregandoProduto = false;
      });

      // Consultar PEC se PEC ativo (mesmo sem barras, tenta com dados basicos)
      if (_pecAtivo && _pecService != null) {
        _consultarPec(detalhesBasicos);
      }

      // Iniciar timer de 60 segundos para limpar o produto da tela
      _iniciarTimerProduto();
    }

    BeepService.playSuccess();
  }

  @override
  void dispose() {
    _productDisplayTimer?.cancel();
    _debounceTimer?.cancel();
    _pesquisaInactivityTimer?.cancel();
    _carrosselTimer?.cancel();
    _carrosselRefreshTimer?.cancel();
    _carrosselScrollController?.dispose();
    _scannerController?.dispose();
    _pesquisaController.removeListener(_onSearchChanged);
    _pesquisaController.dispose();
    _pesquisaFocusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF546E7A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF78909C),
        title: Row(
          children: [
            const Icon(Icons.qr_code_scanner, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              'PriceX',
              style: GoogleFonts.roboto(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _abrirConfiguracoes,
          ),
        ],
      ),
      body: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
    );
  }

  /// Mini badge para lista de pesquisa
  Widget _buildMiniBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Layout para modo paisagem (lado a lado)
  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        // Camera/Pesquisa na esquerda
        SizedBox(
          width: 300,
          child: _buildCameraSearchArea(),
        ),
        // Produto na direita (maior)
        Expanded(
          child: _buildProductArea(),
        ),
      ],
    );
  }

  /// Layout para modo retrato (empilhado)
  Widget _buildPortraitLayout() {
    return Column(
      children: [
        // Camera/Pesquisa no topo
        SizedBox(
          height: 320,
          child: _buildCameraSearchArea(),
        ),
        // Produto no meio
        Expanded(
          child: _buildProductArea(),
        ),
        // Carrossel de promocoes na parte inferior
        if (_produtosCarrossel.isNotEmpty)
          SizedBox(
            height: 200,
            child: _buildCarrosselPromocoes(),
          ),
      ],
    );
  }

  /// Widget combinado Camera/Pesquisa com flex dinamico
  Widget _buildCameraSearchArea() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF546E7A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Coluna da Camera
          Expanded(
            flex: _modoBuscaCamera ? 3 : 1,
            child: _modoBuscaCamera
                ? _buildCameraColuna()
                : _buildCameraMinimizada(),
          ),
          const SizedBox(width: 4),
          // Coluna da Pesquisa
          Expanded(
            flex: _modoBuscaCamera ? 1 : 3,
            child: _modoBuscaCamera
                ? _buildPesquisaMinimizada()
                : _buildPesquisaColuna(),
          ),
        ],
      ),
    );
  }

  /// Camera quando esta ativa (modo camera)
  Widget _buildCameraColuna() {
    // Ativar camera automaticamente se nao estiver ativa
    if (!_cameraAtiva && _modoBuscaCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_cameraAtiva && _modoBuscaCamera) {
          _ativarCamera();
        }
      });
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.green,
          width: 3,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _cameraAtiva ? _buildActiveCamera() : _buildCameraLoading(),
    );
  }

  /// Tela de carregamento da camera
  Widget _buildCameraLoading() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.green),
            SizedBox(height: 12),
            Text(
              'Iniciando camera...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// Camera minimizada (quando pesquisa esta ativa)
  Widget _buildCameraMinimizada() {
    return GestureDetector(
      onTap: _alternarModoBusca,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade600, width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Codigo',
                style: GoogleFonts.roboto(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pesquisa minimizada (quando camera esta ativa) - com animacao pulsante
  Widget _buildPesquisaMinimizada() {
    return GestureDetector(
      onTap: _alternarModoBusca,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green.shade700, Colors.green.shade900],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade400, width: 2),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _pulseAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mic,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pesquisar\npor nome',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pesquisa expandida (quando pesquisa esta ativa)
  Widget _buildPesquisaColuna() {
    return GestureDetector(
      onTap: _reiniciarTimerPesquisa,
      onPanDown: (_) => _reiniciarTimerPesquisa(),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF78909C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blue.shade300, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
        children: [
          // Campo de pesquisa compacto
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF546E7A),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pesquisaController,
                    focusNode: _pesquisaFocusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Digite o produto...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white, size: 20),
                      suffixIcon: _pesquisaController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: Colors.white, size: 18),
                              onPressed: () {
                                _pesquisaController.clear();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _executarPesquisa(),
                  ),
                ),
                // Botao de microfone
                if (_speechDisponivel) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _toggleReconhecimentoVoz,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _ouvindo ? Colors.red : Colors.green.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _ouvindo ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Indicador de escuta
          if (_ouvindo)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.red.shade600,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.graphic_eq, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Ouvindo...',
                    style: GoogleFonts.roboto(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          // Lista de resultados
          Expanded(
            child: _pesquisando
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _resultadosPesquisa.isEmpty
                    ? Center(
                        child: Text(
                          _pesquisaController.text.length < _minCaracteresParaPesquisa
                              ? 'Digite pelo menos $_minCaracteresParaPesquisa letras'
                              : 'Nenhum resultado',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(4),
                        itemCount: _resultadosPesquisa.length,
                        itemBuilder: (context, index) {
                          final produto = _resultadosPesquisa[index];
                          return _buildProdutoListItemCompacto(produto);
                        },
                      ),
          ),
        ],
        ),
      ),
    );
  }

  /// Item compacto da lista de produtos na pesquisa
  Widget _buildProdutoListItemCompacto(Map<String, dynamic> produto) {
    final descricao = produto['descricao'] ?? '';
    final estoque = (produto['estoque'] as num?)?.toInt() ?? 0;
    final temDescQtde = produto['temDescontoQuantidade'] == true;
    final isPromo = produto['isPromocional'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      color: estoque <= 0 ? Colors.grey.shade300 : Colors.white,
      child: InkWell(
        onTap: () => _selecionarProduto(produto),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Badges de promo/qtd (se houver)
              if (isPromo || temDescQtde)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPromo)
                        _buildMiniBadge('P', Colors.green.shade600),
                      if (temDescQtde)
                        Padding(
                          padding: EdgeInsets.only(top: isPromo ? 2 : 0),
                          child: _buildMiniBadge('Q', Colors.purple.shade600),
                        ),
                    ],
                  ),
                ),
              // Nome do produto
              Expanded(
                child: Text(
                  descricao,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: estoque <= 0 ? Colors.grey : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // Estoque no canto direito
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: estoque <= 0
                      ? Colors.red.shade600
                      : estoque <= 5
                          ? Colors.orange.shade600
                          : Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: Colors.white,
                      size: 10,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$estoque',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCamera() {
    // Tamanhos da area de leitura (+20%)
    const double scanWidth = 264.0; // Era 220, +20%
    const double scanHeight = 120.0; // Era 100, +20%
    const double lineWidth = 240.0; // Era 200, +20%

    return LayoutBuilder(
      builder: (context, constraints) {
        final centerX = constraints.maxWidth / 2;
        final centerY = constraints.maxHeight / 2;

        return Stack(
          children: [
            // Fundo escuro (cor solida da loja)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF546E7A), // Azul escuro da marca
              ),
            ),

            // Camera apenas na area de leitura (com ClipRRect)
            Positioned(
              left: centerX - scanWidth / 2,
              top: centerY - scanHeight / 2,
              width: scanWidth,
              height: scanHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _onBarcodeDetect,
                ),
              ),
            ),

            // Linha de mira central (vermelha)
            Center(
              child: Container(
                width: lineWidth,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),

            // Borda da area de mira (retangulo verde)
            Center(
              child: Container(
                width: scanWidth,
                height: scanHeight,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            // Texto instrucao acima da area de leitura
            Positioned(
              top: centerY - scanHeight / 2 - 40,
              left: 0,
              right: 0,
              child: Text(
                'Posicione o codigo de barras na area',
                textAlign: TextAlign.center,
                style: GoogleFonts.roboto(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ),

            // Controle de Zoom na parte inferior
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF78909C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_out, color: Colors.white70, size: 18),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                          activeTrackColor: Colors.green,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.green,
                        ),
                        child: Slider(
                          value: _zoomLevel,
                          min: 0.0,
                          max: 1.0,
                          onChanged: _setZoom,
                        ),
                      ),
                    ),
                    const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),

        // Indicador de carregamento
        if (_carregandoProduto)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),

        // Mensagem de leitura de codigo de barras
        if (_lendoCodigo)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Lendo código de barras...',
                        style: GoogleFonts.roboto(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ],
        );
      },
    );
  }

  Widget _buildProductArea() {
    if (_carregandoProduto) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_mensagemErro != null) {
      return _buildErrorMessage();
    }

    if (_produtoAtual == null) {
      return _buildEmptyState();
    }

    return _buildProductCard();
  }

  Widget _buildEmptyState() {
    return Stack(
      children: [
        // Logo semi-transparente no fundo
        if (_logoLojaPath != null)
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: 0.15,
                child: Image.file(
                  File(_logoLojaPath!),
                  width: 280,
                  height: 280,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        // Conteudo principal
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhum produto',
                style: GoogleFonts.roboto(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use a camera ou pesquise',
                style: GoogleFonts.roboto(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              _mensagemErro!,
              textAlign: TextAlign.center,
              style: GoogleFonts.roboto(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard() {
    final descricao = _produtoAtual!['descricao'] ?? '';
    final fabricante = _produtoAtual!['fabricanteNome'] ?? '';
    final precoCheio = (_produtoAtual!['precoCheio'] as num?)?.toDouble() ?? 0;
    final precoPraticado = (_produtoAtual!['precoPraticado'] as num?)?.toDouble() ?? 0;
    final isPromocional = _produtoAtual!['isPromocional'] == true;
    final origemPreco = _produtoAtual!['origemPreco'] ?? 'NORMAL';
    final estoque = (_produtoAtual!['estoque'] as num?)?.toInt() ?? 0;

    // Informacoes de promocao com data fim
    final diasRestantesPromoRaw = (_produtoAtual!['diasRestantesPromocao'] as num?)?.toInt();
    final promocaoAcabando = diasRestantesPromoRaw != null && diasRestantesPromoRaw >= 0 && diasRestantesPromoRaw <= 5;
    final diasRestantesPromocao = diasRestantesPromoRaw ?? 0;

    // Informacoes de desconto adicional
    final temDescontoQuantidade = _produtoAtual!['temDescontoQuantidade'] == true;
    final sugestaoDescQtde = _produtoAtual!['sugestaoDescontoQtde'] as String?;
    final regrasDescQtde = _produtoAtual!['regrasDescontoQtde'] as List<dynamic>? ?? [];
    final temCombo = _produtoAtual!['temCombo'] == true;
    final combos = _produtoAtual!['combos'] as List<dynamic>? ?? [];
    final temLoteDesconto = _produtoAtual!['temLoteDesconto'] == true;
    final lotesDesconto = _produtoAtual!['lotesDesconto'] as List<dynamic>? ?? [];
    final maiorDescontoLote = (_produtoAtual!['maiorDescontoLote'] as num?)?.toDouble();

    // Verificar tipo de desconto
    final isTabloide = origemPreco.toUpperCase().contains('TABLOIDE');
    final isDescontoAvista = origemPreco.toUpperCase().contains('DESC. A VISTA') ||
                             origemPreco.toUpperCase().contains('DESC. REGRA');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badges de promocao no topo
            if (temDescontoQuantidade || temCombo || temLoteDesconto || isTabloide || isDescontoAvista || _consultandoPec || (_resultadoPec != null && _resultadoPec!.temDesconto))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Badge Tabloide
                    if (isTabloide)
                      _buildBadge(
                        icon: Icons.campaign,
                        label: 'TABLOIDE',
                        colors: [Colors.pink.shade600, Colors.pink.shade400],
                      ),
                    // Badge Desconto a Vista
                    if (isDescontoAvista)
                      _buildBadge(
                        icon: Icons.payments,
                        label: 'À VISTA',
                        colors: [Colors.cyan.shade600, Colors.cyan.shade400],
                      ),
                    // Badge Desconto Quantidade
                    if (temDescontoQuantidade)
                      _buildBadge(
                        icon: Icons.trending_down,
                        label: 'DESC.QTD',
                        colors: [Colors.blue.shade600, Colors.blue.shade400],
                      ),
                    // Badge Combo
                    if (temCombo)
                      _buildBadge(
                        icon: Icons.auto_awesome,
                        label: 'COMBO',
                        colors: [Colors.purple.shade600, Colors.purple.shade400],
                      ),
                    // Badge Lote com Desconto
                    if (temLoteDesconto && maiorDescontoLote != null)
                      _buildBadge(
                        icon: Icons.discount,
                        label: 'LOTE ${maiorDescontoLote.toStringAsFixed(0)}%',
                        colors: [Colors.teal.shade600, Colors.teal.shade400],
                      ),
                    // Badge PEC/Operadora
                    if (_resultadoPec != null && _resultadoPec!.temDesconto)
                      _buildBadge(
                        icon: Icons.card_membership,
                        label: _resultadoPec!.isOfertaJornal ? 'JORNAL $_nomeOperadoraPec' : '$_nomeOperadoraPec ${_resultadoPec!.descontoPercentual.toStringAsFixed(1)}%',
                        colors: [Colors.purple.shade700, Colors.purple.shade500],
                      ),
                    // Indicador consultando PEC/Operadora
                    if (_consultandoPec)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.purple.shade700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$_nomeOperadoraPec...',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.purple.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            // ALERTA: Promocao acabando em breve!
            if (promocaoAcabando && isPromocional)
              _buildPromocaoAcabandoAlert(diasRestantesPromocao),

            // Nome do produto
            Text(
              descricao,
              style: GoogleFonts.roboto(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),

            if (fabricante.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                fabricante,
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Precos
            if (isPromocional) ...[
              Row(
                children: [
                  Text(
                    'De: ',
                    style: GoogleFonts.roboto(fontSize: 14, color: Colors.grey.shade500),
                  ),
                  Text(
                    _currencyFormat.format(precoCheio),
                    style: GoogleFonts.roboto(
                      fontSize: 18,
                      color: Colors.grey.shade500,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],

            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isPromocional ? 'Por: ' : 'Preco: ',
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    color: isPromocional ? Colors.green.shade700 : Colors.grey.shade700,
                  ),
                ),
                Text(
                  _currencyFormat.format(precoPraticado),
                  style: GoogleFonts.roboto(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: isPromocional ? Colors.green.shade700 : const Color(0xFF78909C),
                  ),
                ),
              ],
            ),

            // Tag de origem do preco e economia
            if (isPromocional) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_offer, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          origemPreco.length > 25 ? '${origemPreco.substring(0, 25)}...' : origemPreco,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (precoCheio > precoPraticado)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.savings, color: Colors.orange.shade700, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Economia ${_currencyFormat.format(precoCheio - precoPraticado)}',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],

            // Desconto Quantidade - Faixas de preco
            if (temDescontoQuantidade && regrasDescQtde.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildDescontoQuantidadeSection(regrasDescQtde, precoCheio, precoPraticado, sugestaoDescQtde),
            ],

            // Combo disponivel
            if (temCombo && combos.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildComboSection(combos),
            ],

            // Lote com desconto
            if (temLoteDesconto && lotesDesconto.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildLoteDescontoSection(lotesDesconto),
            ],

            // Desconto PEC
            if (_resultadoPec != null && _resultadoPec!.temDesconto) ...[
              const SizedBox(height: 16),
              _buildPecSection(precoPraticado),
            ],

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: estoque > 0 ? Colors.green.shade600 : Colors.red.shade600,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  estoque > 0 ? 'Estoque: $estoque un.' : 'Sem estoque',
                  style: GoogleFonts.roboto(
                    fontSize: 13,
                    color: estoque > 0 ? Colors.green.shade600 : Colors.red.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Constroi badge de promocao
  Widget _buildBadge({
    required IconData icon,
    required String label,
    required List<Color> colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  /// Alerta chamativo de promocao acabando
  Widget _buildPromocaoAcabandoAlert(int diasRestantes) {
    // Texto dinamico baseado nos dias restantes
    String textoAlerta;
    String textoSecundario;
    List<Color> cores;

    if (diasRestantes == 0) {
      textoAlerta = 'ÚLTIMO DIA DE PROMOÇÃO!';
      textoSecundario = 'Aproveite HOJE, amanhã volta ao preço normal!';
      cores = [Colors.red.shade700, Colors.red.shade500];
    } else if (diasRestantes == 1) {
      textoAlerta = 'PROMOÇÃO ACABA AMANHÃ!';
      textoSecundario = 'Corra! Só mais 1 dia neste preço!';
      cores = [Colors.red.shade600, Colors.orange.shade600];
    } else {
      textoAlerta = 'PROMOÇÃO ACABA EM $diasRestantes DIAS!';
      textoSecundario = 'Aproveite antes que acabe!';
      cores = [Colors.orange.shade600, Colors.amber.shade600];
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: cores,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: cores[0].withValues(alpha: 0.5),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icone animado de alerta
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.timer_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          // Textos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textoAlerta,
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  textoSecundario,
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          // Icone de urgencia
          const Icon(
            Icons.notification_important,
            color: Colors.white,
            size: 28,
          ),
        ],
      ),
    );
  }

  /// Secao de desconto quantidade com layout detalhado por unidade
  /// Mostra o preco praticado (loja) quando for melhor que o desconto quantidade
  Widget _buildDescontoQuantidadeSection(
    List<dynamic> regras,
    double precoCheio,
    double precoPraticado,
    String? sugestao,
  ) {
    // Calcular desconto da loja em relacao ao preco cheio
    final descontoLoja = precoCheio > 0 ? ((precoCheio - precoPraticado) / precoCheio * 100) : 0.0;

    // Calcular totais para mostrar economia
    double totalComDescQtde = 0;

    // Calcular o preco da 1a unidade (base de comparacao)
    double precoUmaUnidade = precoPraticado;
    if (regras.isNotEmpty) {
      final descPrimeiraUnidade = (regras[0]['desconto'] as num?)?.toDouble() ?? 0;
      final precoDescPrimeiraUnidade = precoCheio * (1 - descPrimeiraUnidade / 100);
      // Usar o melhor preco entre desc quantidade da 1a unidade e preco loja
      precoUmaUnidade = precoPraticado < precoDescPrimeiraUnidade
          ? precoPraticado
          : precoDescPrimeiraUnidade;
    }

    // Total se comprar avulso (preco de 1 unidade x quantidade total)
    double totalSemDescQtde = precoUmaUnidade * regras.length;

    for (final regra in regras) {
      final descQtde = (regra['desconto'] as num?)?.toDouble() ?? 0;
      final precoComDescQtde = precoCheio * (1 - descQtde / 100);
      final isGratis = descQtde >= 99;

      // Usar o melhor preco entre desc quantidade e preco loja
      final usaPrecoLoja = !isGratis && precoPraticado < precoComDescQtde;
      final precoFinal = isGratis ? 0.0 : (usaPrecoLoja ? precoPraticado : precoComDescQtde);
      totalComDescQtde += precoFinal;
    }

    final economia = totalSemDescQtde - totalComDescQtde;
    final economiaPerc = totalSemDescQtde > 0 ? (economia / totalSemDescQtde * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.shopping_cart, color: Colors.purple.shade700, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DESCONTO POR QUANTIDADE',
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  Text(
                    'Leve ${regras.length} e pague menos!',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.purple.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Detalhamento por unidade
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Column(
              children: regras.asMap().entries.map((entry) {
                final index = entry.key;
                final regra = entry.value;
                final qtd = (regra['quantidade'] as num?)?.toInt() ?? (index + 1);
                final descQtde = (regra['desconto'] as num?)?.toDouble() ?? 0;
                final precoComDescQtde = precoCheio * (1 - descQtde / 100);
                final isGratis = descQtde >= 99;

                // Verificar qual preco eh melhor: desc quantidade ou preco loja
                final usaPrecoLoja = !isGratis && precoPraticado < precoComDescQtde;
                final precoFinal = isGratis ? 0.0 : (usaPrecoLoja ? precoPraticado : precoComDescQtde);
                final descontoFinal = isGratis ? 100.0 : (usaPrecoLoja ? descontoLoja : descQtde);

                // Cores baseadas no tipo de desconto
                final corBadge = isGratis
                    ? Colors.green.shade100
                    : (usaPrecoLoja ? Colors.blue.shade100 : Colors.purple.shade100);
                final corTextoBadge = isGratis
                    ? Colors.green.shade700
                    : (usaPrecoLoja ? Colors.blue.shade700 : Colors.purple.shade700);
                final corCirculo = isGratis
                    ? Colors.green.shade500
                    : (usaPrecoLoja ? Colors.blue.shade100 : Colors.purple.shade100);
                final corTextoCirculo = isGratis
                    ? Colors.white
                    : (usaPrecoLoja ? Colors.blue.shade700 : Colors.purple.shade700);

                return Padding(
                  padding: EdgeInsets.only(bottom: index < regras.length - 1 ? 8 : 0),
                  child: Row(
                    children: [
                      // Numero da unidade
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: corCirculo,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            '$qtd',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: corTextoCirculo,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Descricao da unidade
                      Expanded(
                        child: Text(
                          '$qtdª unidade',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      // Badge de desconto
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: corBadge,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isGratis
                              ? 'GRÁTIS'
                              : (usaPrecoLoja ? 'LOJA' : '-${descontoFinal.toStringAsFixed(0)}%'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: corTextoBadge,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Preco
                      Text(
                        _currencyFormat.format(precoFinal),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isGratis ? Colors.green.shade600 : Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Resumo de economia
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.shade300),
            ),
            child: Column(
              children: [
                // Linha: Comprando avulso
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Comprando ${regras.length} un avulso:',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      _currencyFormat.format(totalSemDescQtde),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Linha: Com desconto quantidade
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Com desconto quantidade:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                    Text(
                      _currencyFormat.format(totalComDescQtde),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ],
                ),
                if (economia > 0) ...[
                  const Divider(height: 12),
                  // Linha: Economia
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.savings, color: Colors.green.shade600, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'VOCÊ ECONOMIZA:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '-${economiaPerc.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _currencyFormat.format(economia),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
                // Preco medio unitario - destaque
                const Divider(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade600, Colors.purple.shade400],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calculate, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'PREÇO MÉDIO UNITÁRIO:',
                            style: GoogleFonts.roboto(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _currencyFormat.format(totalComDescQtde / regras.length),
                        style: GoogleFonts.roboto(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sugestao
          if (sugestao != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade600],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sugestao,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Secao de combo disponivel com detalhes e produtos
  Widget _buildComboSection(List<dynamic> combos) {
    if (combos.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.amber.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade400, Colors.amber.shade500],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMBO DISPONÍVEL!',
                      style: GoogleFonts.roboto(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    Text(
                      'Junte os produtos e ganhe desconto',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Lista de combos
          ...combos.take(2).map((combo) {
            final descricao = combo['descricao']?.toString() ?? '';
            final produtos = combo['produtos'] as List<dynamic>? ?? [];
            final gruposPreco = combo['gruposPreco'] as List<dynamic>? ?? [];
            final economiaTotal = (combo['economiaTotal'] as num?)?.toDouble() ?? 0;
            final temGruposPreco = combo['temGruposPreco'] == true || gruposPreco.isNotEmpty;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome do combo
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.stars, color: Colors.orange.shade700, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            descricao,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Lista de produtos do combo
                  if (produtos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Produtos do combo:',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...produtos.take(5).map((prod) {
                            final prodDescricao = prod['descricao']?.toString() ?? '';
                            final qtdMinima = (prod['qtdMinima'] as num?)?.toInt() ?? 1;
                            final precoOriginal = (prod['precoOriginal'] as num?)?.toDouble() ?? 0;
                            final precoKit = (prod['precoKit'] as num?)?.toDouble();
                            final descontoPerc = (prod['descontoPerc'] as num?)?.toDouble() ?? 0;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  // Quantidade minima
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$qtdMinima',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Nome do produto
                                  Expanded(
                                    child: Text(
                                      prodDescricao,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // Preco
                                  if (precoKit != null && precoKit > 0) ...[
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        if (descontoPerc > 0)
                                          Text(
                                            _currencyFormat.format(precoOriginal),
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: Colors.grey.shade500,
                                              decoration: TextDecoration.lineThrough,
                                            ),
                                          ),
                                        Text(
                                          _currencyFormat.format(precoKit),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    Text(
                                      _currencyFormat.format(precoOriginal),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                          if (produtos.length > 5)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+ ${produtos.length - 5} produtos...',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Grupos de Preco (outros produtos elegiveis)
                  if (temGruposPreco && gruposPreco.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 8),
                          Row(
                            children: [
                              Icon(Icons.category, color: Colors.purple.shade600, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Grupos de produtos elegiveis:',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.purple.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...gruposPreco.take(3).map((grupo) {
                            final grupoDescricao = grupo['descricao']?.toString() ?? '';
                            final qtdMinima = (grupo['qtdMinima'] as num?)?.toInt() ?? 1;
                            final qtdProdutos = (grupo['qtdProdutosNoGrupo'] as num?)?.toInt() ?? 0;
                            final precoKit = (grupo['precoKit'] as num?)?.toDouble();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.purple.shade200),
                              ),
                              child: Row(
                                children: [
                                  // Quantidade minima
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$qtdMinima',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Nome do grupo
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          grupoDescricao,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.purple.shade700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '$qtdProdutos produtos disponiveis',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.purple.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Preco do kit
                                  if (precoKit != null && precoKit > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _currencyFormat.format(precoKit),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                  // Economia total do combo
                  if (economiaTotal > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                        border: Border(top: BorderSide(color: Colors.green.shade200)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.savings, color: Colors.green.shade700, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'ECONOMIA NO COMBO: ',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                          Text(
                            _currencyFormat.format(economiaTotal),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Secao de lote com desconto
  Widget _buildLoteDescontoSection(List<dynamic> lotes) {
    if (lotes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.discount, color: Colors.teal.shade700, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'LOTE COM DESCONTO',
                style: GoogleFonts.roboto(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...lotes.take(2).map((lote) {
            final loteNome = lote['lote']?.toString() ?? '';
            final desconto = (lote['percDesconto'] as num?)?.toDouble() ?? 0;
            final estoque = (lote['estoque'] as num?)?.toInt() ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lote: $loteNome',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          'Estoque: $estoque un',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade600,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '-${desconto.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Secao de desconto PEC
  Widget _buildPecSection(double precoAtual) {
    if (_resultadoPec == null || !_resultadoPec!.temDesconto) {
      return const SizedBox.shrink();
    }

    final precoPec = _resultadoPec!.precoFinalPec;
    final desconto = _resultadoPec!.descontoPercentual;
    final programa = _resultadoPec!.nomePrograma ?? _nomeOperadoraPec;
    final isJornal = _resultadoPec!.isOfertaJornal;

    // Verificar se o preco PEC eh melhor que o preco atual
    final pecMelhor = precoPec < precoAtual;
    final economia = precoAtual - precoPec;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.purple.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.purple.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.card_membership, color: Colors.purple.shade700, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isJornal ? 'OFERTA JORNAL $_nomeOperadoraPec' : 'DESCONTO $_nomeOperadoraPec',
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                    if (programa.isNotEmpty)
                      Text(
                        programa,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.purple.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              if (!isJornal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade600,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '-${desconto.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PREÇO COM $_nomeOperadoraPec',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currencyFormat.format(precoPec),
                        style: GoogleFonts.roboto(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: pecMelhor ? Colors.purple.shade700 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (pecMelhor && economia > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.savings, color: Colors.green.shade700, size: 16),
                        const SizedBox(height: 2),
                        Text(
                          'ECONOMIZE',
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _currencyFormat.format(economia),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!pecMelhor)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Preco loja\nmelhor!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Carrossel de promocoes estilo ticker/marquee
  Widget _buildCarrosselPromocoes() {
    return Container(
      color: const Color(0xFF78909C),
      child: Column(
        children: [
          // Header do carrossel
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFF546E7A),
            child: Row(
              children: [
                Icon(Icons.local_offer, color: Colors.yellow.shade600, size: 18),
                const SizedBox(width: 8),
                Text(
                  'PROMOCOES EM DESTAQUE',
                  style: GoogleFonts.roboto(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward, color: Colors.white54, size: 16),
              ],
            ),
          ),
          // Lista de produtos em scroll horizontal
          Expanded(
            child: ListView.builder(
              controller: _carrosselScrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _produtosCarrossel.length * 2, // Duplicar para loop infinito
              itemBuilder: (context, index) {
                final produto = _produtosCarrossel[index % _produtosCarrossel.length];
                return _buildCarrosselItem(produto);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Item individual do carrossel de promocoes
  Widget _buildCarrosselItem(Map<String, dynamic> item) {
    // Verificar se e um combo
    if (item['isCombo'] == true) {
      return _buildComboCard(item);
    }
    // E um produto normal
    return _buildProdutoCard(item);
  }

  /// Card de produto individual no carrossel
  Widget _buildProdutoCard(Map<String, dynamic> produto) {
    final descricao = produto['descricao'] ?? '';
    final precoCheio = (produto['precoCheio'] as num?)?.toDouble() ?? 0;
    final precoPraticado = (produto['precoPraticado'] as num?)?.toDouble() ?? 0;
    final descontoPerc = precoCheio > 0
        ? ((precoCheio - precoPraticado) / precoCheio * 100)
        : 0.0;
    final temDescontoPromocional = descontoPerc > 0;

    // Info de promocao (data fim)
    final diasRestantesPromocao = (produto['diasRestantesPromocao'] as num?)?.toInt();
    final promocaoAcabando = diasRestantesPromocao != null && diasRestantesPromocao <= 15 && diasRestantesPromocao >= 0;
    final ultimoDia = diasRestantesPromocao == 0;

    // Identificar tipo de desconto pela origem do preco
    final origemPreco = produto['origemPreco'] as String? ?? 'NORMAL';
    final isTabloide = origemPreco.toUpperCase().contains('TABLOIDE');
    final isDescontoAvista = origemPreco.toUpperCase().contains('DESC. A VISTA') ||
                             origemPreco.toUpperCase().contains('DESC. REGRA');

    // Info de desconto quantidade
    final temDescontoQuantidade = produto['temDescontoQuantidade'] == true;
    final tipoDescontoQtde = produto['tipoDescontoQtde'] as String?;
    final textoDescontoQtde = produto['textoDescontoQtde'] as String?;
    final descontoQtdePercentual = (produto['descontoQtdePercentual'] as num?)?.toDouble();
    final precoUnitarioComDescQtde = (produto['precoUnitarioComDescQtde'] as num?)?.toDouble();
    final qtdeMinimaDesconto = (produto['qtdeMinimaDesconto'] as num?)?.toInt();

    // Determinar cores do card baseado no tipo de desconto
    List<Color> gradientColors;
    Color? borderColor;
    if (temDescontoQuantidade) {
      if (tipoDescontoQtde == 'caixa_gratis') {
        gradientColors = [Colors.purple.shade50, Colors.purple.shade100];
        borderColor = Colors.purple.shade400;
      } else {
        gradientColors = [Colors.orange.shade50, Colors.orange.shade100];
        borderColor = Colors.orange.shade400;
      }
    } else if (temDescontoPromocional) {
      if (isTabloide) {
        gradientColors = [Colors.blue.shade50, Colors.blue.shade100];
        borderColor = Colors.blue.shade400;
      } else if (isDescontoAvista) {
        gradientColors = [Colors.cyan.shade50, Colors.cyan.shade100];
        borderColor = Colors.cyan.shade400;
      } else {
        gradientColors = [Colors.green.shade50, Colors.green.shade100];
        borderColor = Colors.green.shade400;
      }
    } else {
      gradientColors = [Colors.white, Colors.grey.shade50];
      borderColor = null;
    }

    return Container(
      width: 300,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(10),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com badge de desconto quantidade destacado
          if (temDescontoQuantidade)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: tipoDescontoQtde == 'caixa_gratis'
                      ? [Colors.purple.shade600, Colors.purple.shade800]
                      : [Colors.orange.shade600, Colors.orange.shade800],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Icon(
                    tipoDescontoQtde == 'caixa_gratis'
                        ? Icons.card_giftcard
                        : Icons.local_offer,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      textoDescontoQtde ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (descontoQtdePercentual != null && descontoQtdePercentual > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '-${descontoQtdePercentual.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Header com badge de promocao/tabloide/desconto a vista (quando NAO tem desconto quantidade)
          if (temDescontoPromocional && !temDescontoQuantidade)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isTabloide
                      ? [Colors.blue.shade600, Colors.blue.shade800]
                      : isDescontoAvista
                          ? [Colors.cyan.shade600, Colors.cyan.shade800]
                          : [Colors.green.shade600, Colors.green.shade800],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Icon(
                    isTabloide
                        ? Icons.menu_book
                        : isDescontoAvista
                            ? Icons.payments
                            : Icons.local_offer,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isTabloide
                          ? 'OFERTA TABLOIDE'
                          : isDescontoAvista
                              ? 'DESCONTO À VISTA'
                              : 'PROMOÇÃO',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '-${descontoPerc.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (promocaoAcabando) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: ultimoDia ? Colors.red.shade700 : Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ultimoDia ? Icons.warning_amber : Icons.schedule,
                            color: Colors.white,
                            size: 10,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            ultimoDia ? 'ÚLTIMO DIA!' : '${diasRestantesPromocao}d',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Nome do produto
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(10, (temDescontoQuantidade || temDescontoPromocional) ? 4 : 8, 10, 4),
            decoration: (temDescontoQuantidade || temDescontoPromocional)
                ? null
                : BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  ),
            child: Text(
              descricao,
              style: GoogleFonts.roboto(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Linha inferior com precos
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  // Precos
                  Expanded(
                    child: temDescontoQuantidade
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Preco normal por unidade
                              Row(
                                children: [
                                  Text(
                                    _currencyFormat.format(precoPraticado),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  Text(
                                    ' /un',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                              // Preco unitario na promocao
                              if (precoUnitarioComDescQtde != null && precoUnitarioComDescQtde > 0)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      _currencyFormat.format(precoUnitarioComDescQtde),
                                      style: GoogleFonts.roboto(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: tipoDescontoQtde == 'caixa_gratis'
                                            ? Colors.purple.shade700
                                            : Colors.orange.shade700,
                                      ),
                                    ),
                                    Text(
                                      ' /un',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: tipoDescontoQtde == 'caixa_gratis'
                                            ? Colors.purple.shade600
                                            : Colors.orange.shade600,
                                      ),
                                    ),
                                    if (qtdeMinimaDesconto != null)
                                      Text(
                                        tipoDescontoQtde == 'caixa_gratis'
                                            ? ' lev. $qtdeMinimaDesconto'
                                            : ' levando $qtdeMinimaDesconto',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (temDescontoPromocional)
                                Text(
                                  'De: ${_currencyFormat.format(precoCheio)}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade500,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              Row(
                                children: [
                                  if (temDescontoPromocional)
                                    Text(
                                      'Por: ',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: isTabloide
                                            ? Colors.blue.shade700
                                            : isDescontoAvista
                                                ? Colors.cyan.shade700
                                                : Colors.green.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  Text(
                                    _currencyFormat.format(precoPraticado),
                                    style: GoogleFonts.roboto(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: temDescontoPromocional
                                          ? (isTabloide
                                              ? Colors.blue.shade700
                                              : isDescontoAvista
                                                  ? Colors.cyan.shade700
                                                  : Colors.green.shade700)
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Card de combo/kit no carrossel
  Widget _buildComboCard(Map<String, dynamic> combo) {
    final descricao = combo['descricao'] ?? 'Combo';
    final produtos = combo['produtos'] as List<dynamic>? ?? [];
    final gruposPreco = combo['gruposPreco'] as List<dynamic>? ?? [];
    final diasRestantes = (combo['diasRestantes'] as num?)?.toInt();
    final promocaoAcabando = diasRestantes != null && diasRestantes <= 15 && diasRestantes >= 0;
    final ultimoDia = diasRestantes == 0;

    // Calcular economia total do combo
    double precoTotalOriginal = 0;
    double precoTotalCombo = 0;
    for (final p in produtos) {
      final prod = p as Map<String, dynamic>;
      final quantidade = (prod['quantidade'] as num?)?.toInt() ?? 1;
      final precoOriginal = (prod['precoOriginal'] as num?)?.toDouble() ?? 0;
      final precoKit = (prod['precoKit'] as num?)?.toDouble() ?? precoOriginal;
      precoTotalOriginal += precoOriginal * quantidade;
      precoTotalCombo += precoKit * quantidade;
    }
    for (final g in gruposPreco) {
      final grupo = g as Map<String, dynamic>;
      final quantidade = (grupo['quantidade'] as num?)?.toInt() ?? 1;
      final precoKit = (grupo['precoKit'] as num?)?.toDouble() ?? 0;
      // Para grupos, usamos o preco do kit como referencia
      precoTotalCombo += precoKit * quantidade;
    }
    final economiaTotal = precoTotalOriginal - precoTotalCombo;
    final temEconomia = economiaTotal > 0.01;

    // Combinar todos os itens (produtos + grupos)
    final List<Widget> todosItens = [];
    for (final p in produtos) {
      todosItens.add(_buildComboProdutoItem(p as Map<String, dynamic>));
    }
    for (final g in gruposPreco) {
      todosItens.add(_buildComboGrupoItem(g as Map<String, dynamic>));
    }

    // Decidir layout: 2 colunas se tiver 3+ itens
    final usarDuasColunas = todosItens.length >= 3;

    return Container(
      width: 320,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.deepPurple.shade50, Colors.deepPurple.shade100],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade400, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header do combo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade600, Colors.deepPurple.shade800],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    descricao.length > 25 ? '${descricao.substring(0, 25)}...' : descricao,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'COMBO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Dias restantes ao lado de COMBO
                if (promocaoAcabando) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: ultimoDia ? Colors.red : Colors.orange,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, size: 10, color: Colors.white),
                        const SizedBox(width: 2),
                        Text(
                          ultimoDia ? 'ÚLTIMO DIA!' : '${diasRestantes}d',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Conteudo - Lista de produtos
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: usarDuasColunas
                  ? _buildComboGridLayout(todosItens)
                  : _buildComboListLayout(todosItens),
            ),
          ),

          // Footer com economia total
          if (temEconomia)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.savings, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'ECONOMIZE ${_currencyFormat.format(economiaTotal)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Layout em lista (1 coluna) para poucos itens
  Widget _buildComboListLayout(List<Widget> itens) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: itens,
      ),
    );
  }

  /// Layout em grid (2 colunas) para 3+ itens
  Widget _buildComboGridLayout(List<Widget> itens) {
    // Dividir itens em 2 colunas
    final List<Widget> colunaEsquerda = [];
    final List<Widget> colunaDireita = [];
    for (int i = 0; i < itens.length; i++) {
      if (i % 2 == 0) {
        colunaEsquerda.add(itens[i]);
      } else {
        colunaDireita.add(itens[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: colunaEsquerda,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: colunaDireita,
          ),
        ),
      ],
    );
  }

  /// Item de produto dentro do card de combo (simplificado)
  Widget _buildComboProdutoItem(Map<String, dynamic> produto) {
    final descricao = produto['descricao'] ?? '';
    final quantidade = (produto['quantidade'] as num?)?.toInt() ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // Quantidade
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade100,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${quantidade}x',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Descricao
          Expanded(
            child: Text(
              descricao,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Item de grupo de preco dentro do card de combo (simplificado)
  Widget _buildComboGrupoItem(Map<String, dynamic> grupo) {
    final descricao = grupo['descricao'] ?? '';
    final quantidade = (grupo['quantidade'] as num?)?.toInt() ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.deepPurple.shade300, width: 0.5),
      ),
      child: Row(
        children: [
          // Icone de grupo
          Icon(
            Icons.category,
            size: 10,
            color: Colors.deepPurple.shade500,
          ),
          const SizedBox(width: 3),
          // Quantidade
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade200,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${quantidade}x',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Descricao
          Expanded(
            child: Text(
              descricao,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: Colors.deepPurple.shade700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
