import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../modelos/gestao.dart';
import '../../servicos/gestao_servico.dart';
import '../../servicos/imagem_servico.dart';
import '../../servicos/pedidos_servico.dart';
import '../../util/formatar.dart';
import '../../widgets/comum.dart';

/// Criar ou editar produto: foto, nome, descrição, preço, categoria e grupos de opções
class TelaProduto extends StatefulWidget {
  final Produto? produto;
  final int? idCategoriaInicial;
  const TelaProduto({super.key, this.produto, this.idCategoriaInicial});

  @override
  State<TelaProduto> createState() => _TelaProdutoState();
}

class _TelaProdutoState extends State<TelaProduto> {
  final _gestao = GestaoServico.instancia;
  late final _nome = TextEditingController(text: widget.produto?.nomeProduto);
  late final _descricao = TextEditingController(text: widget.produto?.descricaoProduto);
  late final _preco =
      TextEditingController(text: widget.produto == null ? '' : numeroParaCampo(widget.produto!.precoProduto));
  late int _idCategoria = widget.produto?.idCategoria ?? widget.idCategoriaInicial ?? _gestao.categorias.first.id;
  late String? _fotoUrl = widget.produto?.fotoUrl;
  // a ordem dos grupos é a ordem em que foram marcados
  late final List<int> _grupos = [...?widget.produto?.idsGrupos];
  bool _enviandoFoto = false;
  bool _salvando = false;

  bool get _editando => widget.produto != null;

  Future<void> _escolherFoto() async {
    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Tirar foto'),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          if (_fotoUrl != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remover foto'),
              onTap: () {
                Navigator.pop(c);
                setState(() => _fotoUrl = null);
              },
            ),
        ]),
      ),
    );
    if (origem == null) return;
    setState(() => _enviandoFoto = true);
    try {
      final url = await ImagemServico.instancia.escolherEEnviar(
        idEmpresa: PedidosServico.instancia.empresa!.id,
        tipo: TipoImagem.produtos,
        origem: origem,
      );
      if (url != null) setState(() => _fotoUrl = url);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
    if (mounted) setState(() => _enviandoFoto = false);
  }

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) return mostrarMensagem(context, 'Informe o nome do produto.');
    if (_preco.text.trim().isEmpty) return mostrarMensagem(context, 'Informe o preço.');
    setState(() => _salvando = true);
    try {
      await _gestao.salvarProduto(
        existente: widget.produto,
        idCategoria: _idCategoria,
        nome: nome,
        descricao: _descricao.text,
        preco: lerNumero(_preco.text),
        fotoUrl: _fotoUrl,
        idsGrupos: _grupos,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        mostrarErro(context, e);
        setState(() => _salvando = false);
      }
    }
  }

  Future<void> _excluir() async {
    final ok = await confirmar(context,
        titulo: 'Excluir "${widget.produto!.nomeProduto}"?', botao: 'Excluir', perigo: true);
    if (!ok || !mounted) return;
    try {
      await _gestao.excluirProduto(widget.produto!);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final grupos = [..._gestao.grupos]..sort(compararOrdem);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar produto' : 'Novo produto'),
        actions: [
          if (_editando)
            IconButton(tooltip: 'Excluir produto', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: InkWell(
            onTap: _enviandoFoto ? null : _escolherFoto,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: cores.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cores.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: _enviandoFoto
                  ? const Center(child: CircularProgressIndicator())
                  : _fotoUrl == null
                      ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_a_photo, size: 36, color: cores.primary),
                          const SizedBox(height: 6),
                          const Text('Adicionar foto'),
                        ])
                      : Image.network(_fotoUrl!, fit: BoxFit.cover),
            ),
          ),
        ),
        if (_fotoUrl != null)
          Center(child: TextButton(onPressed: _escolherFoto, child: const Text('Trocar foto'))),
        const SizedBox(height: 16),
        TextField(
          controller: _nome,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: X-Bacon', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descricao,
          textCapitalization: TextCapitalization.sentences,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Descrição (opcional)',
            hintText: 'Ex.: Pão, hambúrguer 150g, bacon, queijo e salada',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: CampoMoeda(controle: _preco)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _idCategoria,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
              items: [
                for (final c in _gestao.categorias)
                  DropdownMenuItem(value: c.id, child: Text(c.nomeCategoria, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _idCategoria = v!),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        Text('Adicionais e opções', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          grupos.isEmpty
              ? 'Você ainda não criou grupos. Crie na aba "Adicionais e opções" do Cardápio (ex.: Escolha o pão, Adicionais).'
              : 'Marque o que o cliente pode escolher neste produto.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        for (final g in grupos)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _grupos.contains(g.id),
            onChanged: (v) => setState(() => v! ? _grupos.add(g.id) : _grupos.remove(g.id)),
            title: Text(g.nomeGrupo + (g.ativo ? '' : ' (oculto)')),
            subtitle: Text(
              '${g.regra}${g.opcoes.isEmpty ? '' : ' · ${g.opcoes.map((o) => o.nomeOpcao).join(', ')}'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            secondary: _grupos.contains(g.id)
                ? CircleAvatar(radius: 12, child: Text('${_grupos.indexOf(g.id) + 1}', style: const TextStyle(fontSize: 12)))
                : null,
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _salvando || _enviandoFoto ? null : _salvar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(_salvando ? 'Salvando...' : 'Salvar produto'),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _nome.dispose();
    _descricao.dispose();
    _preco.dispose();
    super.dispose();
  }
}
