import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/beep_service.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';
import 'config_screen.dart';

class PriceScannerScreen extends StatefulWidget {
  const PriceScannerScreen({super.key});

  @override
  State<PriceScannerScreen> createState() => _PriceScannerScreenState();
}

class _PriceScannerScreenState extends State<PriceScannerScreen> {
  // Controlador da camera
  MobileScannerController? _scannerController;
  bool _cameraAtiva = false;
  bool _processandoLeitura = false;

  // Zoom da camera
  double _zoomLevel = 0.0;

  // Timer de inatividade da camera (20 segundos)
  Timer? _inactivityTimer;
  static const Duration _inactivityTimeout = Duration(seconds: 20);

  // Contagem regressiva visivel (camera)
  int _secondsRemaining = 0;
  Timer? _countdownTimer;

  // Timer para limpar produto da tela (60 segundos)
  Timer? _productDisplayTimer;
  static const Duration _productDisplayTimeout = Duration(seconds: 60);

  // Dados do produto atual
  Map<String, dynamic>? _produtoAtual;
  bool _carregandoProduto = false;
  String? _mensagemErro;

  // Mensagem de leitura de codigo
  bool _lendoCodigo = false;

  // Pesquisa
  final _pesquisaController = TextEditingController();
  final _pesquisaFocusNode = FocusNode();
  List<Map<String, dynamic>> _resultadosPesquisa = [];
  bool _pesquisando = false;
  bool _mostrarPesquisa = false;
  Timer? _debounceTimer;
  static const int _minCaracteresParaPesquisa = 2;
  static const Duration _debounceDelay = Duration(milliseconds: 400);

  // Reconhecimento de voz
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechDisponivel = false;
  bool _ouvindo = false;

  // Tabela de desconto
  int _tabelaDescontoId = 1;

  // Formatador de moeda
  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _inicializarReconhecimentoVoz();
    // Adicionar listener para pesquisa automatica
    _pesquisaController.addListener(_onSearchChanged);
  }

  Future<void> _carregarConfiguracoes() async {
    _tabelaDescontoId = await ConfigService.getTabelaDescontoId();

    // Verificar se tem configuracao
    final hasConfig = await ConfigService.hasConfig();
    if (!hasConfig && mounted) {
      _abrirConfiguracoes();
    }
  }

  /// Inicializa o reconhecimento de voz
  Future<void> _inicializarReconhecimentoVoz() async {
    _speechDisponivel = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) {
            setState(() => _ouvindo = false);
          }
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _ouvindo = false);
        }
        debugPrint('[Speech] Erro: $error');
      },
    );
    if (mounted) {
      setState(() {});
    }
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
      await _speech.stop();
      setState(() => _ouvindo = false);
    } else {
      setState(() => _ouvindo = true);

      await _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            final texto = result.recognizedWords;
            if (texto.isNotEmpty) {
              _pesquisaController.text = texto;
              // Mover cursor para o final
              _pesquisaController.selection = TextSelection.fromPosition(
                TextPosition(offset: _pesquisaController.text.length),
              );
            }
            setState(() => _ouvindo = false);
          }
        },
        localeId: 'pt_BR',
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.search,
          cancelOnError: true,
          partialResults: false,
        ),
      );
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
  }

  void _ativarCamera() {
    if (_cameraAtiva) return;

    // Fechar pesquisa se estiver aberta
    setState(() {
      _mostrarPesquisa = false;
      _cameraAtiva = true;
      _secondsRemaining = _inactivityTimeout.inSeconds;
      _zoomLevel = 0.0;
    });

    _scannerController = MobileScannerController(
      facing: CameraFacing.front,
      detectionSpeed: DetectionSpeed.normal,
    );

    _iniciarTimerInatividade();
    _iniciarContadorRegressivo();
  }

  void _desativarCamera() {
    _inactivityTimer?.cancel();
    _countdownTimer?.cancel();

    _scannerController?.dispose();
    _scannerController = null;

    setState(() {
      _cameraAtiva = false;
      _secondsRemaining = 0;
    });
  }

  void _setZoom(double value) {
    setState(() {
      _zoomLevel = value;
    });
    _scannerController?.setZoomScale(value);
  }

  void _iniciarTimerInatividade() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, () {
      // Tempo esgotado - desativar camera e limpar produto
      _desativarCamera();
      setState(() {
        _produtoAtual = null;
        _mensagemErro = null;
      });
    });
  }

  void _iniciarContadorRegressivo() {
    _countdownTimer?.cancel();
    _secondsRemaining = _inactivityTimeout.inSeconds;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _reiniciarTimers() {
    _iniciarTimerInatividade();
    _iniciarContadorRegressivo();
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

    // Reiniciar timers ao detectar codigo
    _reiniciarTimers();

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

  // ========== PESQUISA ==========

  void _togglePesquisa() {
    setState(() {
      _mostrarPesquisa = !_mostrarPesquisa;
      if (_mostrarPesquisa) {
        _desativarCamera();
        // Focar no campo de pesquisa
        Future.delayed(const Duration(milliseconds: 100), () {
          _pesquisaFocusNode.requestFocus();
        });
      } else {
        _pesquisaController.clear();
        _resultadosPesquisa = [];
      }
    });
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
      _mostrarPesquisa = false;
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
        // Iniciar timer de 60 segundos para limpar o produto da tela
        _iniciarTimerProduto();
      }
    } else {
      // Fallback para dados basicos se nao tiver barras
      setState(() {
        _produtoAtual = {
          'sucesso': true,
          ...produto,
        };
        _carregandoProduto = false;
      });
      // Iniciar timer de 60 segundos para limpar o produto da tela
      _iniciarTimerProduto();
    }

    BeepService.playSuccess();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _countdownTimer?.cancel();
    _productDisplayTimer?.cancel();
    _debounceTimer?.cancel();
    _scannerController?.dispose();
    _pesquisaController.removeListener(_onSearchChanged);
    _pesquisaController.dispose();
    _pesquisaFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
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
          // Botao de pesquisa
          IconButton(
            icon: Icon(
              _mostrarPesquisa ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: _togglePesquisa,
            tooltip: 'Pesquisar produto',
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _abrirConfiguracoes,
          ),
        ],
      ),
      body: _mostrarPesquisa
          ? _buildPesquisaView()
          : (isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout()),
    );
  }

  /// View de pesquisa
  Widget _buildPesquisaView() {
    return Column(
      children: [
        // Campo de pesquisa
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1565C0),
          child: Column(
            children: [
              // Campo de texto com botao de microfone ao lado
              Row(
                children: [
                  // Campo de pesquisa
                  Expanded(
                    child: TextField(
                      controller: _pesquisaController,
                      focusNode: _pesquisaFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: InputDecoration(
                        hintText: 'Digite o nome do produto...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                        prefixIcon: const Icon(Icons.search, color: Colors.white, size: 28),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Loading ou botao limpar
                            if (_pesquisando)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            else if (_pesquisaController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white, size: 24),
                                onPressed: () {
                                  _pesquisaController.clear();
                                },
                              ),
                          ],
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _executarPesquisa(),
                      onChanged: (value) {
                        setState(() {});
                      },
                    ),
                  ),
                  // Botao grande de microfone
                  if (_speechDisponivel) ...[
                    const SizedBox(width: 12),
                    _buildMicrophoneButton(),
                  ],
                ],
              ),
              // Indicador de escuta por voz (animado e chamativo)
              if (_ouvindo)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade400, Colors.red.shade600],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.graphic_eq, color: Colors.white, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        'Ouvindo... Fale o nome do produto',
                        style: GoogleFonts.roboto(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              // Dica de uso
              else if (_pesquisaController.text.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Digite ou toque no microfone para pesquisar por voz',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Resultados
        Expanded(
          child: _resultadosPesquisa.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _pesquisaController.text.length < _minCaracteresParaPesquisa
                            ? Icons.keyboard
                            : Icons.search_off,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _pesquisaController.text.length < _minCaracteresParaPesquisa
                            ? 'Digite pelo menos $_minCaracteresParaPesquisa caracteres'
                            : 'Nenhum produto encontrado',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _resultadosPesquisa.length,
                  itemBuilder: (context, index) {
                    final produto = _resultadosPesquisa[index];
                    return _buildProdutoListItem(produto);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProdutoListItem(Map<String, dynamic> produto) {
    final descricao = produto['descricao'] ?? '';
    final fabricante = produto['fabricanteNome'] ?? '';
    final estoque = (produto['estoque'] as num?)?.toInt() ?? 0;
    final temDescQtde = produto['temDescontoQuantidade'] == true;
    final origemPreco = produto['origemPreco'] ?? 'NORMAL';
    final isTabloide = origemPreco.toString().toUpperCase().contains('TABLOIDE');
    final isPromo = produto['isPromocional'] == true;
    final temCombo = produto['temCombo'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: estoque <= 0 ? Colors.grey.shade200 : Colors.white,
      child: InkWell(
        onTap: () => _selecionarProduto(produto),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Informacoes do produto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badges no topo
                    if (temDescQtde || isTabloide || isPromo || temCombo)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Wrap(
                          spacing: 4,
                          children: [
                            if (isPromo)
                              _buildMiniBadge('PROMO', Colors.green.shade600),
                            if (isTabloide)
                              _buildMiniBadge('TAB', Colors.pink.shade600),
                            if (temDescQtde)
                              _buildMiniBadge('QTD', Colors.purple.shade600),
                            if (temCombo)
                              _buildMiniBadge('COMBO', Colors.orange.shade600),
                          ],
                        ),
                      ),
                    // Nome do produto
                    Text(
                      descricao,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: estoque <= 0 ? Colors.grey.shade600 : Colors.grey.shade800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (fabricante.isNotEmpty)
                      Text(
                        fabricante,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    // Estoque
                    Row(
                      children: [
                        Icon(
                          estoque > 0 ? Icons.check_circle : Icons.cancel,
                          size: 12,
                          color: estoque > 0 ? Colors.green.shade600 : Colors.red.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          estoque > 0 ? 'Estoque: $estoque' : 'Sem estoque',
                          style: TextStyle(
                            fontSize: 11,
                            color: estoque > 0 ? Colors.green.shade600 : Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Seta para indicar clique
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Botao grande e chamativo de microfone para pesquisa por voz
  Widget _buildMicrophoneButton() {
    return GestureDetector(
      onTap: _toggleReconhecimentoVoz,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _ouvindo
                ? [Colors.red.shade400, Colors.red.shade700]
                : [Colors.green.shade400, Colors.green.shade700],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (_ouvindo ? Colors.red : Colors.green).withValues(alpha: 0.5),
              blurRadius: _ouvindo ? 16 : 10,
              spreadRadius: _ouvindo ? 2 : 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Icone principal
            Icon(
              _ouvindo ? Icons.mic : Icons.mic_none,
              color: Colors.white,
              size: 36,
            ),
            // Indicador de gravacao (pulso)
            if (_ouvindo)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
        // Camera na esquerda (menor)
        SizedBox(
          width: 280,
          child: _buildCameraArea(),
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
        // Camera no topo
        SizedBox(
          height: 280,
          child: _buildCameraArea(),
        ),
        // Produto embaixo
        Expanded(
          child: _buildProductArea(),
        ),
      ],
    );
  }

  Widget _buildCameraArea() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _cameraAtiva ? Colors.green : Colors.grey.shade600,
          width: 3,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _cameraAtiva ? _buildActiveCamera() : _buildInactiveCamera(),
    );
  }

  Widget _buildInactiveCamera() {
    return InkWell(
      onTap: _ativarCamera,
      child: Container(
        color: Colors.grey.shade900,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app,
                size: 48,
                color: Colors.blue.shade300,
              ),
              const SizedBox(height: 12),
              Text(
                'Toque para ativar',
                style: GoogleFonts.roboto(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ou use a pesquisa',
                style: GoogleFonts.roboto(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCamera() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Stack(
      children: [
        // Camera com rotacao para corrigir orientacao em paisagem
        Positioned.fill(
          child: isLandscape
              ? Transform.rotate(
                  angle: -math.pi / 2, // Rotaciona 90 graus
                  child: MobileScanner(
                    controller: _scannerController,
                    onDetect: _onBarcodeDetect,
                  ),
                )
              : MobileScanner(
                  controller: _scannerController,
                  onDetect: _onBarcodeDetect,
                ),
        ),

        // Linha de mira central
        Center(
          child: Container(
            width: isLandscape ? 150 : 200,
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

        // Area de mira (retangulo)
        Center(
          child: Container(
            width: isLandscape ? 180 : 220,
            height: isLandscape ? 80 : 100,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // Timer no canto superior direito
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _secondsRemaining <= 5 ? Colors.red : Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${_secondsRemaining}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Botao para desativar camera
        Positioned(
          top: 8,
          left: 8,
          child: InkWell(
            onTap: _desativarCamera,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),

        // Controle de Zoom na parte inferior
        Positioned(
          bottom: 8,
          left: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.zoom_out, color: Colors.white, size: 16),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      value: _zoomLevel,
                      min: 0.0,
                      max: 1.0,
                      activeColor: Colors.green,
                      inactiveColor: Colors.grey,
                      onChanged: _setZoom,
                    ),
                  ),
                ),
                const Icon(Icons.zoom_in, color: Colors.white, size: 16),
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
    return Center(
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

    // Verificar se eh tabloide
    final isTabloide = origemPreco.toUpperCase().contains('TABLOIDE');

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
            if (temDescontoQuantidade || temCombo || temLoteDesconto || isTabloide)
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
                    color: isPromocional ? Colors.green.shade700 : const Color(0xFF1565C0),
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
    double totalSemDescQtde = precoPraticado * regras.length; // Total se comprar avulso (preco loja)

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
}
