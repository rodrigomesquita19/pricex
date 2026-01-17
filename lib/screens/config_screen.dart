import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/database_config.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';
import 'grupos_exibicao_screen.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '3306');
  final _databaseController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _deviceIp;

  // Tabelas de desconto
  List<Map<String, dynamic>> _tabelasDesconto = [];
  int? _tabelaDescontoSelecionada;
  String? _tabelaDescontoNome;
  bool _carregandoTabelas = false;

  // PEC (Programa de Economia Colaborativa)
  final _pecCartaoController = TextEditingController();
  bool _pecAtivo = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadDeviceIp();
  }

  Future<void> _loadDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (!ip.startsWith('127.') && !ip.startsWith('169.254.')) {
            if (mounted) {
              setState(() => _deviceIp = ip);
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao obter IP do dispositivo: $e');
    }
  }

  void _autoPreencherDados() {
    setState(() {
      _hostController.text = '192.168.15.51';
      _portController.text = '3306';
      _databaseController.text = 'vendas';
      _usernameController.text = 'root';
      _passwordController.text = '123456big';
      _tabelaDescontoSelecionada = 1;
      _tabelaDescontoNome = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dados preenchidos automaticamente'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);

    final config = await ConfigService.getConfig();
    if (config != null) {
      _hostController.text = config.host;
      _portController.text = config.port.toString();
      _databaseController.text = config.database;
      _usernameController.text = config.username;
      _passwordController.text = config.password;
    }

    final tabelaDesconto = await ConfigService.getTabelaDescontoId();
    _tabelaDescontoSelecionada = tabelaDesconto;

    // Carregar config PEC
    final pecCartao = await ConfigService.getCartaoPec();
    if (pecCartao != null) {
      _pecCartaoController.text = pecCartao;
    }
    _pecAtivo = await ConfigService.isPecAtivo();

    setState(() => _isLoading = false);
  }

  /// Carrega as tabelas de desconto do banco de dados
  Future<void> _carregarTabelasDesconto() async {
    setState(() => _carregandoTabelas = true);

    try {
      final tabelas = await DatabaseService.buscarTabelasDesconto();

      if (mounted) {
        setState(() {
          _tabelasDesconto = tabelas;
          _carregandoTabelas = false;

          // Atualizar nome da tabela selecionada
          if (_tabelaDescontoSelecionada != null) {
            final tabelaAtual = tabelas.firstWhere(
              (t) => t['id'] == _tabelaDescontoSelecionada,
              orElse: () => <String, dynamic>{},
            );
            if (tabelaAtual.isNotEmpty) {
              _tabelaDescontoNome = tabelaAtual['descricao'];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar tabelas de desconto: $e');
      if (mounted) {
        setState(() => _carregandoTabelas = false);
      }
    }
  }

  /// Abre o dialog para selecionar tabela de desconto
  Future<void> _selecionarTabelaDesconto() async {
    // Primeiro verifica se tem conexao configurada
    final config = await ConfigService.getConfig();
    if (config == null || !config.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configure a conexao com o banco primeiro'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Carregar tabelas se ainda nao foram carregadas
    if (_tabelasDesconto.isEmpty) {
      await _carregarTabelasDesconto();
    }

    if (_tabelasDesconto.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel carregar as tabelas de desconto'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    // Mostrar dialog de selecao
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade600, Colors.green.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.discount, color: Colors.white, size: 28),
                      SizedBox(height: 10),
                      Text(
                        'Selecione a Tabela de Desconto',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de tabelas
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _tabelasDesconto.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                    itemBuilder: (context, index) {
                      final tabela = _tabelasDesconto[index];
                      final isSelected = tabela['id'] == _tabelaDescontoSelecionada;

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.green.shade100
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isSelected ? Icons.check_circle : Icons.discount_outlined,
                            color: isSelected
                                ? Colors.green.shade600
                                : Colors.grey.shade600,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          tabela['descricao'] ?? 'Sem nome',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? Colors.green.shade700 : Colors.grey.shade800,
                          ),
                        ),
                        subtitle: Text(
                          'ID: ${tabela['id']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check, color: Colors.green.shade600, size: 20)
                            : Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                        onTap: () => Navigator.pop(dialogContext, tabela),
                      );
                    },
                  ),
                ),

                // Botao cancelar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (resultado != null && mounted) {
      setState(() {
        _tabelaDescontoSelecionada = resultado['id'];
        _tabelaDescontoNome = resultado['descricao'];
      });
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final config = DatabaseConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text) ?? 3306,
      database: _databaseController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    // Testar conexao antes de salvar
    final testResult = await DatabaseService.testConnectionDetailed(config);

    if (!testResult.success) {
      setState(() => _isLoading = false);

      if (!mounted) return;

      IconData errorIcon;
      Color errorColor;
      String errorTitle;

      switch (testResult.errorType) {
        case ConnectionErrorType.serverNotFound:
          errorIcon = Icons.cloud_off;
          errorColor = Colors.red;
          errorTitle = 'Servidor nao encontrado';
          break;
        case ConnectionErrorType.databaseNotFound:
          errorIcon = Icons.storage_outlined;
          errorColor = Colors.orange;
          errorTitle = 'Banco nao encontrado';
          break;
        case ConnectionErrorType.authFailed:
          errorIcon = Icons.lock_outline;
          errorColor = Colors.red;
          errorTitle = 'Autenticacao falhou';
          break;
        default:
          errorIcon = Icons.warning_amber_rounded;
          errorColor = Colors.orange;
          errorTitle = 'Conexao Falhou';
      }

      final salvarMesmoAssim = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(errorIcon, color: errorColor, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(errorTitle)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: errorColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: errorColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        testResult.message,
                        style: TextStyle(
                          color: errorColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Deseja salvar mesmo assim?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Salvar Mesmo Assim'),
            ),
          ],
        ),
      );

      if (salvarMesmoAssim != true) return;

      setState(() => _isLoading = true);
    }

    await ConfigService.saveConfig(config);

    // Salvar tabela de desconto
    await ConfigService.saveTabelaDescontoId(_tabelaDescontoSelecionada ?? 1);

    // Salvar config PEC
    await ConfigService.saveCartaoPec(_pecCartaoController.text.trim());
    await ConfigService.savePecAtivo(_pecAtivo);

    // Fechar conexao antiga
    await DatabaseService.closeConnection();

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(testResult.success
            ? 'Conexao testada e configuracao salva!'
            : 'Configuracao salva (conexao nao testada)'),
          backgroundColor: testResult.success ? Colors.green : Colors.orange,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pecCartaoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Configuracoes',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Secao Banco de Dados
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade300,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.storage, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Conexao com Banco de Dados',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _autoPreencherDados,
                                icon: const Icon(Icons.flash_on, size: 16),
                                label: const Text('Auto', style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.orange.shade700,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                              ),
                            ],
                          ),

                          if (_deviceIp != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.wifi, size: 18, color: Colors.blue.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'IP deste dispositivo:',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                        Text(
                                          _deviceIp!,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                            color: Colors.blue.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _hostController,
                            decoration: const InputDecoration(
                              labelText: 'Host / IP do Servidor',
                              hintText: 'Ex: 192.168.1.100',
                              prefixIcon: Icon(Icons.computer),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Informe o host do servidor';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: 'Porta',
                              hintText: '3306',
                              prefixIcon: Icon(Icons.lan),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _databaseController,
                            decoration: const InputDecoration(
                              labelText: 'Nome do Banco de Dados',
                              hintText: 'Ex: vendas',
                              prefixIcon: Icon(Icons.folder),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Informe o nome do banco';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Usuario',
                              hintText: 'Ex: root',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Informe o usuario';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Senha',
                              prefixIcon: const Icon(Icons.lock),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Secao Tabela de Desconto
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade300,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.discount, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Regras de Preco',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'A tabela de desconto define as regras de preco praticado para cada produto.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Seletor de tabela de desconto
                          InkWell(
                            onTap: _carregandoTabelas ? null : _selecionarTabelaDesconto,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.discount,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Tabela de Desconto',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        _carregandoTabelas
                                            ? const SizedBox(
                                                height: 16,
                                                width: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : Text(
                                                _tabelaDescontoNome ??
                                                  (_tabelaDescontoSelecionada != null
                                                    ? 'ID: $_tabelaDescontoSelecionada'
                                                    : 'Toque para selecionar'),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: _tabelaDescontoNome != null
                                                      ? FontWeight.w500
                                                      : FontWeight.normal,
                                                  color: _tabelaDescontoNome != null
                                                      ? Colors.grey.shade800
                                                      : Colors.grey.shade500,
                                                ),
                                              ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Secao PEC (Programa de Economia Colaborativa)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade300,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.card_membership, color: Colors.purple.shade700),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'PEC - Programa de Economia',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _pecAtivo,
                                onChanged: (value) {
                                  setState(() => _pecAtivo = value);
                                },
                                activeColor: Colors.purple.shade600,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Consulta descontos do cartao fidelidade PEC ao bipar produtos.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),

                          if (_pecAtivo) ...[
                            const SizedBox(height: 16),

                            // Cartao PEC (unico campo necessario)
                            TextFormField(
                              controller: _pecCartaoController,
                              decoration: InputDecoration(
                                labelText: 'Numero do Cartao PEC',
                                hintText: 'Ex: 21156911307',
                                prefixIcon: Icon(Icons.credit_card, color: Colors.purple.shade600),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.purple.shade50,
                                helperText: 'Os demais parametros sao carregados automaticamente',
                                helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Secao Carrossel de Promocoes
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade300,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.slideshow, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Carrossel de Promocoes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Configure grupos de produtos para exibir promocoes quando o tablet estiver ocioso.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Botao para acessar configuracao do carrossel
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GruposExibicaoScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.orange.shade300),
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.orange.shade50,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.category,
                                      color: Colors.orange.shade700,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Configurar Grupos',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Defina quais produtos aparecerao no carrossel',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.orange.shade600,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveConfig,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isLoading ? 'Testando conexao...' : 'Salvar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }
}
