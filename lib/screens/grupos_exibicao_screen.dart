import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/grupo_exibicao.dart';
import '../services/config_service.dart';
import '../services/database_service.dart';

class GruposExibicaoScreen extends StatefulWidget {
  const GruposExibicaoScreen({super.key});

  @override
  State<GruposExibicaoScreen> createState() => _GruposExibicaoScreenState();
}

class _GruposExibicaoScreenState extends State<GruposExibicaoScreen> {
  List<GrupoExibicao> _grupos = [];
  bool _carregando = true;
  bool _carrosselAtivo = false;
  bool _combosAtivo = true;
  int _tempoCarrossel = 10;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);

    final grupos = await ConfigService.getGruposExibicao();
    final carrosselAtivo = await ConfigService.isCarrosselAtivo();
    final combosAtivo = await ConfigService.isCombosCarrosselAtivo();
    final velocidadeCarrossel = await ConfigService.getVelocidadeCarrossel();

    if (mounted) {
      setState(() {
        _grupos = grupos;
        _carrosselAtivo = carrosselAtivo;
        _combosAtivo = combosAtivo;
        _tempoCarrossel = velocidadeCarrossel;
        _carregando = false;
      });
    }
  }

  Future<void> _toggleCarrossel(bool valor) async {
    await ConfigService.saveCarrosselAtivo(valor);
    setState(() => _carrosselAtivo = valor);
  }

  Future<void> _toggleCombos(bool valor) async {
    await ConfigService.saveCombosCarrosselAtivo(valor);
    setState(() => _combosAtivo = valor);
  }

  Future<void> _alterarVelocidadeCarrossel() async {
    final niveis = [1, 2, 3, 4, 5, 6, 7, 8, 9];

    final resultado = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Velocidade do Carrossel'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: niveis.map((n) => ListTile(
              title: Text(ConfigService.getNomeVelocidade(n)),
              leading: Radio<int>(
                value: n,
                groupValue: _tempoCarrossel,
                onChanged: (v) => Navigator.pop(context, v),
              ),
              onTap: () => Navigator.pop(context, n),
            )).toList(),
          ),
        ),
      ),
    );

    if (resultado != null) {
      await ConfigService.saveVelocidadeCarrossel(resultado);
      setState(() => _tempoCarrossel = resultado);
    }
  }

  Future<void> _adicionarGrupo() async {
    final resultado = await Navigator.push<GrupoExibicao>(
      context,
      MaterialPageRoute(
        builder: (_) => const EditarGrupoExibicaoScreen(),
      ),
    );

    if (resultado != null) {
      await ConfigService.addGrupoExibicao(resultado);
      await _carregarDados();
    }
  }

  Future<void> _editarGrupo(GrupoExibicao grupo) async {
    final resultado = await Navigator.push<GrupoExibicao>(
      context,
      MaterialPageRoute(
        builder: (_) => EditarGrupoExibicaoScreen(grupo: grupo),
      ),
    );

    if (resultado != null) {
      await ConfigService.updateGrupoExibicao(resultado);
      await _carregarDados();
    }
  }

  Future<void> _removerGrupo(GrupoExibicao grupo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Grupo'),
        content: Text('Deseja remover o grupo "${grupo.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await ConfigService.removeGrupoExibicao(grupo.id);
      await _carregarDados();
    }
  }

  Future<void> _toggleGrupoAtivo(GrupoExibicao grupo) async {
    final novoGrupo = grupo.copyWith(ativo: !grupo.ativo);
    await ConfigService.updateGrupoExibicao(novoGrupo);
    await _carregarDados();
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
          'Carrossel de Promocoes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Configuracoes gerais do carrossel
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
                            Icon(Icons.slideshow, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            const Text(
                              'Configuracoes do Carrossel',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Exibe promocoes quando o tablet esta ocioso',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Switch para ativar/desativar
                        SwitchListTile(
                          title: const Text('Carrossel Ativo'),
                          subtitle: Text(
                            _carrosselAtivo
                                ? 'Exibira promocoes quando ocioso'
                                : 'Desativado',
                            style: TextStyle(
                              color: _carrosselAtivo
                                  ? Colors.green.shade600
                                  : Colors.grey.shade600,
                            ),
                          ),
                          value: _carrosselAtivo,
                          onChanged: _toggleCarrossel,
                          activeColor: Colors.green,
                        ),

                        // Switch para exibir combos
                        SwitchListTile(
                          title: const Text('Exibir Combos/Kits'),
                          subtitle: Text(
                            _combosAtivo
                                ? 'Combos ativos serao exibidos'
                                : 'Combos desativados',
                            style: TextStyle(
                              color: _combosAtivo
                                  ? Colors.deepPurple.shade600
                                  : Colors.grey.shade600,
                            ),
                          ),
                          value: _combosAtivo,
                          onChanged: _toggleCombos,
                          activeColor: Colors.deepPurple,
                        ),

                        const Divider(),

                        // Velocidade do carrossel
                        ListTile(
                          leading: Icon(Icons.speed, color: Colors.blue.shade600),
                          title: const Text('Velocidade de Passagem'),
                          subtitle: Text(ConfigService.getNomeVelocidade(_tempoCarrossel)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _alterarVelocidadeCarrossel,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Header dos grupos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Grupos de Produtos',
                        style: GoogleFonts.roboto(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _adicionarGrupo,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Novo Grupo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Lista de grupos
                  if (_grupos.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum grupo configurado',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Adicione grupos para exibir no carrossel',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(_grupos.length, (index) {
                      final grupo = _grupos[index];
                      return _buildGrupoCard(grupo, index);
                    }),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildGrupoCard(GrupoExibicao grupo, int index) {
    final corTipo = switch (grupo.tipo) {
      TipoFiltroGrupo.grupo => Colors.blue,
      TipoFiltroGrupo.especificacao => Colors.purple,
      TipoFiltroGrupo.principioAtivo => Colors.teal,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: grupo.ativo ? corTipo.shade200 : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header do card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: grupo.ativo
                  ? corTipo.shade50
                  : Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                // Icone do tipo
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: grupo.ativo
                        ? corTipo.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    switch (grupo.tipo) {
                      TipoFiltroGrupo.grupo => Icons.category,
                      TipoFiltroGrupo.especificacao => Icons.label,
                      TipoFiltroGrupo.principioAtivo => Icons.science,
                    },
                    color: grupo.ativo ? corTipo.shade700 : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Nome e tipo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        grupo.nome,
                        style: GoogleFonts.roboto(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: grupo.ativo
                              ? Colors.grey.shade800
                              : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        grupo.tipoDescricao,
                        style: TextStyle(
                          fontSize: 11,
                          color: grupo.ativo
                              ? corTipo.shade600
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Switch ativo
                Switch(
                  value: grupo.ativo,
                  onChanged: (_) => _toggleGrupoAtivo(grupo),
                  activeColor: corTipo,
                ),
              ],
            ),
          ),

          // Corpo do card
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Itens selecionados
                Row(
                  children: [
                    Icon(Icons.checklist, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${grupo.idsItens.length} item(ns) selecionado(s)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (grupo.nomesItens.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    grupo.nomesItens.take(3).join(', ') +
                        (grupo.nomesItens.length > 3
                            ? ' e mais ${grupo.nomesItens.length - 3}...'
                            : ''),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 8),

                // Filtro
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_alt, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        grupo.filtroDescricao,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Botoes de acao
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _editarGrupo(grupo),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Editar'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _removerGrupo(grupo),
                      icon: const Icon(Icons.delete, size: 16),
                      label: const Text('Remover'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== TELA DE EDICAO DE GRUPO =====

class EditarGrupoExibicaoScreen extends StatefulWidget {
  final GrupoExibicao? grupo;

  const EditarGrupoExibicaoScreen({super.key, this.grupo});

  @override
  State<EditarGrupoExibicaoScreen> createState() => _EditarGrupoExibicaoScreenState();
}

class _EditarGrupoExibicaoScreenState extends State<EditarGrupoExibicaoScreen> {
  final _nomeController = TextEditingController();
  TipoFiltroGrupo _tipoSelecionado = TipoFiltroGrupo.grupo;
  FiltroEstoqueDesconto _filtroSelecionado = FiltroEstoqueDesconto.todos;

  List<Map<String, dynamic>> _itensDisponiveis = [];
  Set<int> _itensSelecionados = {};
  final Map<int, String> _nomesItens = {};

  bool _carregandoItens = false;
  String _termoPesquisa = '';

  @override
  void initState() {
    super.initState();

    if (widget.grupo != null) {
      _nomeController.text = widget.grupo!.nome;
      _tipoSelecionado = widget.grupo!.tipo;
      _filtroSelecionado = widget.grupo!.filtro;
      _itensSelecionados = widget.grupo!.idsItens.toSet();
      for (int i = 0; i < widget.grupo!.idsItens.length; i++) {
        if (i < widget.grupo!.nomesItens.length) {
          _nomesItens[widget.grupo!.idsItens[i]] = widget.grupo!.nomesItens[i];
        }
      }
    }

    _carregarItens();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    super.dispose();
  }

  Future<void> _carregarItens() async {
    setState(() => _carregandoItens = true);

    List<Map<String, dynamic>> itens;
    switch (_tipoSelecionado) {
      case TipoFiltroGrupo.grupo:
        itens = await DatabaseService.buscarGruposProdutos();
        break;
      case TipoFiltroGrupo.especificacao:
        itens = await DatabaseService.buscarEspecificacoes();
        break;
      case TipoFiltroGrupo.principioAtivo:
        itens = await DatabaseService.buscarPrincipiosAtivos();
        break;
    }

    if (mounted) {
      setState(() {
        _itensDisponiveis = itens;
        _carregandoItens = false;

        // Atualizar nomes dos itens selecionados
        for (final item in itens) {
          if (_itensSelecionados.contains(item['id'])) {
            _nomesItens[item['id']] = item['descricao'];
          }
        }
      });
    }
  }

  void _alterarTipo(TipoFiltroGrupo? tipo) {
    if (tipo != null && tipo != _tipoSelecionado) {
      setState(() {
        _tipoSelecionado = tipo;
        _itensSelecionados.clear();
        _nomesItens.clear();
        _itensDisponiveis = [];
      });
      _carregarItens();
    }
  }

  void _toggleItem(int id, String nome) {
    setState(() {
      if (_itensSelecionados.contains(id)) {
        _itensSelecionados.remove(id);
        _nomesItens.remove(id);
      } else {
        _itensSelecionados.add(id);
        _nomesItens[id] = nome;
      }
    });
  }

  void _salvar() {
    if (_nomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um nome para o grupo'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_itensSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione pelo menos um item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final grupo = GrupoExibicao(
      id: widget.grupo?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nome: _nomeController.text.trim(),
      tipo: _tipoSelecionado,
      idsItens: _itensSelecionados.toList(),
      nomesItens: _itensSelecionados.map((id) => _nomesItens[id] ?? '').toList(),
      filtro: _filtroSelecionado,
      ativo: widget.grupo?.ativo ?? true,
      criadoEm: widget.grupo?.criadoEm ?? DateTime.now(),
    );

    Navigator.pop(context, grupo);
  }

  List<Map<String, dynamic>> get _itensFiltrados {
    if (_termoPesquisa.isEmpty) return _itensDisponiveis;
    final termo = _termoPesquisa.toLowerCase();
    return _itensDisponiveis
        .where((item) =>
            (item['descricao'] as String).toLowerCase().contains(termo))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.grupo != null;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Editar Grupo' : 'Novo Grupo',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: _salvar,
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('Salvar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Formulario superior
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome do grupo
                TextField(
                  controller: _nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Grupo',
                    hintText: 'Ex: Promocoes de Bebidas',
                    prefixIcon: Icon(Icons.label),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // Tipo de filtro
                DropdownButtonFormField<TipoFiltroGrupo>(
                  value: _tipoSelecionado,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Filtro',
                    prefixIcon: Icon(Icons.filter_list),
                    border: OutlineInputBorder(),
                  ),
                  items: TipoFiltroGrupo.values.map((tipo) {
                    return DropdownMenuItem(
                      value: tipo,
                      child: Text(switch (tipo) {
                        TipoFiltroGrupo.grupo => 'Grupo de Produtos',
                        TipoFiltroGrupo.especificacao => 'Especificacao',
                        TipoFiltroGrupo.principioAtivo => 'Principio Ativo',
                      }),
                    );
                  }).toList(),
                  onChanged: _alterarTipo,
                ),

                const SizedBox(height: 16),

                // Filtro de estoque/desconto
                DropdownButtonFormField<FiltroEstoqueDesconto>(
                  value: _filtroSelecionado,
                  decoration: const InputDecoration(
                    labelText: 'Filtro de Produtos',
                    prefixIcon: Icon(Icons.tune),
                    border: OutlineInputBorder(),
                  ),
                  items: FiltroEstoqueDesconto.values.map((filtro) {
                    return DropdownMenuItem(
                      value: filtro,
                      child: Text(switch (filtro) {
                        FiltroEstoqueDesconto.todos => 'Todos os produtos e combos',
                        FiltroEstoqueDesconto.comDesconto => 'Somente com desconto',
                        FiltroEstoqueDesconto.descontoEEstoque => 'Com desconto e estoque',
                      }),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _filtroSelecionado = v);
                  },
                ),
              ],
            ),
          ),

          // Barra de pesquisa
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Pesquisar...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => setState(() => _termoPesquisa = v),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_itensSelecionados.length} selecionado(s)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lista de itens
          Expanded(
            child: _carregandoItens
                ? const Center(child: CircularProgressIndicator())
                : _itensFiltrados.isEmpty
                    ? Center(
                        child: Text(
                          _termoPesquisa.isEmpty
                              ? 'Nenhum item encontrado'
                              : 'Nenhum resultado para "$_termoPesquisa"',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _itensFiltrados.length,
                        itemBuilder: (context, index) {
                          final item = _itensFiltrados[index];
                          final id = item['id'] as int;
                          final descricao = item['descricao'] as String;
                          final selecionado = _itensSelecionados.contains(id);

                          return ListTile(
                            leading: Checkbox(
                              value: selecionado,
                              onChanged: (_) => _toggleItem(id, descricao),
                              activeColor: Colors.green,
                            ),
                            title: Text(
                              descricao,
                              style: TextStyle(
                                fontWeight: selecionado
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              'ID: $id',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            onTap: () => _toggleItem(id, descricao),
                            selected: selecionado,
                            selectedTileColor: Colors.green.shade50,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
