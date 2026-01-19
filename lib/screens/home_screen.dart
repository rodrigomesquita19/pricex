import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart' show pararModoKiosk;
import '../services/config_service.dart';
import '../services/database_service.dart';
import 'config_screen.dart';
import 'price_scanner_screen.dart';

// Controllers para login
final _loginUsuarioController = TextEditingController();
final _loginSenhaController = TextEditingController();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _verificandoConfig = true;
  bool _bancoConfigurado = false;
  bool _tabelaDescontoConfigurada = false;
  String? _logoLojaPath;
  String? _mensagemStatus;

  @override
  void initState() {
    super.initState();
    _verificarConfiguracoes();
  }

  Future<void> _verificarConfiguracoes() async {
    setState(() {
      _verificandoConfig = true;
      _mensagemStatus = 'Verificando configurações...';
    });

    try {
      // Verificar se banco está configurado
      final hasConfig = await ConfigService.hasConfig();
      _bancoConfigurado = hasConfig;

      if (hasConfig) {
        // Tentar conexão
        setState(() => _mensagemStatus = 'Testando conexão...');
        final conn = await DatabaseService.getConnection();
        _bancoConfigurado = conn != null;

        if (_bancoConfigurado) {
          // Verificar tabela de desconto
          setState(() => _mensagemStatus = 'Verificando tabela de desconto...');
          final tabelaId = await ConfigService.getTabelaDescontoId();
          _tabelaDescontoConfigurada = tabelaId > 0;
        }
      }

      // Carregar logo da loja
      final logoPath = await ConfigService.getLogoLoja();
      if (logoPath != null && File(logoPath).existsSync()) {
        _logoLojaPath = logoPath;
      }

      _mensagemStatus = null;
    } catch (e) {
      debugPrint('[HomeScreen] Erro ao verificar configurações: $e');
      _mensagemStatus = 'Erro ao verificar configurações';
    }

    if (mounted) {
      setState(() => _verificandoConfig = false);
    }
  }

  bool get _podeIniciar => _bancoConfigurado && _tabelaDescontoConfigurada;

  void _iniciar() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PriceScannerScreen()),
    );
  }

  void _abrirConfiguracoes() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfigScreen(apenasConexao: true)),
    );

    // Recarregar configurações após voltar
    if (result == true || result == null) {
      _verificarConfiguracoes();
    }
  }

  void _abrirConfiguracoesDesconto() async {
    // Verificar se banco está configurado
    if (!_bancoConfigurado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure a conexão com o banco primeiro'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Solicitar autenticação
    final autenticado = await _mostrarDialogoLogin();
    if (!autenticado) return;

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfigScreen(apenasConexao: false)),
    );

    // Recarregar configurações após voltar
    if (result == true || result == null) {
      _verificarConfiguracoes();
    }
  }

  /// Mostra dialogo de login e retorna true se autenticado com sucesso
  Future<bool> _mostrarDialogoLogin() async {
    _loginUsuarioController.clear();
    _loginSenhaController.clear();
    bool obscurePassword = true;
    bool isLoading = false;
    String? errorMessage;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF37474F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.lock, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Autenticação',
                    style: GoogleFonts.roboto(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Informe suas credenciais para acessar as configurações de desconto',
                      style: GoogleFonts.roboto(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _loginUsuarioController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Usuário',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.person, color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.blue),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _loginSenhaController,
                      obscureText: obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        labelStyle: const TextStyle(color: Colors.white70),
                        prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setDialogState(() => obscurePassword = !obscurePassword);
                          },
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white30),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.blue),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.1),
                      ),
                      onSubmitted: (_) async {
                        if (isLoading) return;
                        setDialogState(() {
                          isLoading = true;
                          errorMessage = null;
                        });

                        final loginResult = await DatabaseService.loginUsuario(
                          _loginUsuarioController.text.trim(),
                          _loginSenhaController.text,
                        );

                        if (!context.mounted) return;

                        if (loginResult['success'] == true) {
                          Navigator.pop(dialogContext, true);
                        } else {
                          setDialogState(() {
                            isLoading = false;
                            errorMessage = loginResult['message'] ?? 'Erro ao autenticar';
                          });
                        }
                      },
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: GoogleFonts.roboto(
                                  color: Colors.red.shade200,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(dialogContext, false),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          setDialogState(() {
                            isLoading = true;
                            errorMessage = null;
                          });

                          final loginResult = await DatabaseService.loginUsuario(
                            _loginUsuarioController.text.trim(),
                            _loginSenhaController.text,
                          );

                          if (!context.mounted) return;

                          if (loginResult['success'] == true) {
                            Navigator.pop(dialogContext, true);
                          } else {
                            setDialogState(() {
                              isLoading = false;
                              errorMessage = loginResult['message'] ?? 'Erro ao autenticar';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Entrar'),
                ),
              ],
            );
          },
        );
      },
    );

    return result == true;
  }

  void _sairDoAplicativo() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF455A64),
        title: Text(
          'Sair do Aplicativo',
          style: GoogleFonts.roboto(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente sair do aplicativo?',
          style: GoogleFonts.roboto(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      // Parar modo kiosk antes de fechar
      await pararModoKiosk();
      // Fechar o aplicativo completamente
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF546E7A),
      body: SafeArea(
        child: Stack(
          children: [
            // Logo de fundo (se configurado)
            if (_logoLojaPath != null)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.08,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.15, 0.15, 0.15, 0, 30,
                      0.15, 0.15, 0.15, 0, 30,
                      0.15, 0.15, 0.15, 0, 30,
                      0,    0,    0,    1, 0,
                    ]),
                    child: Image.file(
                      File(_logoLojaPath!),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),

            // Conteúdo principal
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo/Título do App
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'PriceX',
                      style: GoogleFonts.roboto(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Verificador de Preços',
                      style: GoogleFonts.roboto(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Status de configuração
                    if (_verificandoConfig) ...[
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        _mensagemStatus ?? 'Verificando...',
                        style: GoogleFonts.roboto(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ] else ...[
                      // Indicadores de status
                      _buildStatusIndicator(
                        icon: Icons.storage,
                        label: 'Banco de Dados',
                        isOk: _bancoConfigurado,
                      ),
                      const SizedBox(height: 8),
                      _buildStatusIndicator(
                        icon: Icons.discount,
                        label: 'Tabela de Desconto',
                        isOk: _tabelaDescontoConfigurada,
                      ),

                      const SizedBox(height: 32),

                      // Mensagem se não pode iniciar
                      if (!_podeIniciar)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Configure o sistema para iniciar',
                                style: GoogleFonts.roboto(
                                  color: Colors.orange.shade100,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 32),

                      // Botão Iniciar
                      SizedBox(
                        width: 250,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _podeIniciar ? _iniciar : null,
                          icon: const Icon(Icons.play_arrow, size: 28),
                          label: Text(
                            'Iniciar',
                            style: GoogleFonts.roboto(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade600,
                            disabledForegroundColor: Colors.grey.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Botão Config. Banco
                      SizedBox(
                        width: 250,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _abrirConfiguracoes,
                          icon: const Icon(Icons.storage),
                          label: Text(
                            'Config. Banco',
                            style: GoogleFonts.roboto(fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Botão Config. Desconto (requer autenticação)
                      SizedBox(
                        width: 250,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _bancoConfigurado ? _abrirConfiguracoesDesconto : null,
                          icon: const Icon(Icons.lock),
                          label: Text(
                            'Config. Desconto',
                            style: GoogleFonts.roboto(fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _bancoConfigurado ? Colors.amber.shade200 : Colors.grey,
                            side: BorderSide(
                              color: _bancoConfigurado ? Colors.amber.shade400 : Colors.grey.shade600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Botão Sair
                      TextButton.icon(
                        onPressed: _sairDoAplicativo,
                        icon: const Icon(Icons.exit_to_app, size: 18),
                        label: Text(
                          'Sair',
                          style: GoogleFonts.roboto(fontSize: 14),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator({
    required IconData icon,
    required String label,
    required bool isOk,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isOk ? Colors.green : Colors.red.shade300,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.roboto(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isOk ? Icons.check_circle : Icons.cancel,
            color: isOk ? Colors.green : Colors.red.shade300,
            size: 18,
          ),
        ],
      ),
    );
  }
}
