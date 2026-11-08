import 'package:flutter/material.dart';

import '../../modelos/gestao.dart';
import '../../servicos/gestao_servico.dart';
import '../../tema.dart';
import '../../util/formatar.dart';
import '../../widgets/comum.dart';
import 'tela_produto.dart';

/// Categorias e seus produtos. Toque no produto para editar.
class AbaProdutos extends StatelessWidget {
  final bool ordenando;
  final Future<void> Function() aoAtualizar;
  const AbaProdutos({super.key, required this.ordenando, required this.aoAtualizar});

  GestaoServico get _gestao => GestaoServico.instancia;

  Future<void> _executar(BuildContext context, Future<void> Function() acao) async {
    try {
      await acao();
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  }

  Future<void> _novaCategoria(BuildContext context) async {
    final nome = await pedirTexto(context, titulo: 'Nova categoria', rotulo: 'Ex.: Lanches, Bebidas', botao: 'Criar');
    if (nome != null && context.mounted) await _executar(context, () => _gestao.criarCategoria(nome));
  }

  void _abrirProduto(BuildContext context, {Produto? produto, int? idCategoria}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TelaProduto(produto: produto, idCategoriaInicial: idCategoria)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categorias = _gestao.categorias;
    if (categorias.isEmpty) {
      return EstadoVazio(
        icone: Icons.restaurant_menu,
        texto: 'Seu cardápio está vazio.\nComece criando uma categoria, por exemplo "Lanches".',
        acao: FilledButton.icon(
          onPressed: () => _novaCategoria(context),
          icon: const Icon(Icons.add),
          label: const Text('Criar categoria'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: aoAtualizar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Esp.m, Esp.m, Esp.m, 40),
        children: [
          if (ordenando)
            const Dica('Use as setas para mudar a ordem em que aparecem no cardápio. Toque em "Pronto" quando terminar.')
          else
            const Dica('Toque num produto para editar. Desligue "À venda" quando acabar o estoque.'),
          for (var i = 0; i < categorias.length; i++) _cartaoCategoria(context, categorias, i),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _novaCategoria(context),
            icon: const Icon(Icons.add),
            label: const Text('Nova categoria'),
          ),
        ],
      ),
    );
  }

  Widget _cartaoCategoria(BuildContext context, List<Categoria> categorias, int indice) {
    final c = categorias[indice];
    final produtos = _gestao.produtosDa(c.id);
    final cores = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: Esp.m),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
          child: Row(children: [
            Expanded(
              child: Text(c.nomeCategoria,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: c.ativo ? null : cores.outline,
                    decoration: c.ativo ? null : TextDecoration.lineThrough,
                  )),
            ),
            if (!c.ativo)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Chip(label: Text('Escondida'), visualDensity: VisualDensity.compact),
              ),
            if (ordenando)
              BotoesOrdem(
                aoSubir: indice > 0 ? () => _executar(context, () => _gestao.mover('categorias', categorias, indice, -1)) : null,
                aoDescer: indice < categorias.length - 1
                    ? () => _executar(context, () => _gestao.mover('categorias', categorias, indice, 1))
                    : null,
              )
            else
              PopupMenuButton<String>(
                tooltip: 'Editar categoria',
                icon: const Icon(Icons.edit_outlined),
                onSelected: (v) => _acaoCategoria(context, c, v, produtos.length),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'renomear', child: Text('Renomear')),
                  PopupMenuItem(value: 'ativo', child: Text(c.ativo ? 'Esconder do cardápio' : 'Mostrar no cardápio')),
                  const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                ],
              ),
          ]),
        ),
        if (produtos.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Nenhum produto ainda.', style: TextStyle(color: Cores.textoSuave)),
          ),
        for (var j = 0; j < produtos.length; j++) _linhaProduto(context, produtos, j),
        if (!ordenando)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: OutlinedButton.icon(
              onPressed: () => _abrirProduto(context, idCategoria: c.id),
              icon: const Icon(Icons.add),
              label: Text('Adicionar em ${c.nomeCategoria}', overflow: TextOverflow.ellipsis),
            ),
          )
        else
          const SizedBox(height: 8),
      ]),
    );
  }

  Widget _linhaProduto(BuildContext context, List<Produto> produtos, int indice) {
    final p = produtos[indice];
    final cores = Theme.of(context).colorScheme;
    final grupos = p.idsGrupos.length;
    return ListTile(
      key: ValueKey(p.id),
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      minVerticalPadding: 10,
      leading: Opacity(opacity: p.ativo ? 1 : 0.5, child: Miniatura(url: p.fotoUrl, nome: p.nomeProduto)),
      title: Text(p.nomeProduto, style: TextStyle(color: p.ativo ? null : cores.outline)),
      subtitle: Text.rich(TextSpan(children: [
        TextSpan(
          text: formatarMoeda(p.precoProduto),
          style: const TextStyle(fontWeight: FontWeight.w700, color: Cores.texto),
        ),
        if (grupos > 0) TextSpan(text: '  ·  $grupos ${grupos == 1 ? 'grupo de adicionais' : 'grupos de adicionais'}'),
      ])),
      onTap: ordenando ? null : () => _abrirProduto(context, produto: p),
      trailing: ordenando
          ? BotoesOrdem(
              aoSubir: indice > 0 ? () => _executar(context, () => _gestao.mover('produtos', produtos, indice, -1)) : null,
              aoDescer: indice < produtos.length - 1
                  ? () => _executar(context, () => _gestao.mover('produtos', produtos, indice, 1))
                  : null,
            )
          : InterruptorRotulado(
              valor: p.ativo,
              ligado: 'À venda',
              desligado: 'Esgotado',
              aoMudar: (_) => _executar(context, () => _gestao.alternarProduto(p)),
            ),
    );
  }

  Future<void> _acaoCategoria(BuildContext context, Categoria c, String acao, int qtdProdutos) async {
    switch (acao) {
      case 'renomear':
        final nome = await pedirTexto(context, titulo: 'Renomear categoria', inicial: c.nomeCategoria);
        if (nome != null && context.mounted) await _executar(context, () => _gestao.renomearCategoria(c, nome));
      case 'ativo':
        await _executar(context, () => _gestao.alternarCategoria(c));
      case 'excluir':
        final ok = await confirmar(
          context,
          titulo: 'Excluir "${c.nomeCategoria}"?',
          texto: qtdProdutos > 0
              ? 'Os $qtdProdutos produto(s) desta categoria também serão excluídos.'
              : 'A categoria está vazia.',
          botao: 'Excluir',
          perigo: true,
        );
        if (ok && context.mounted) await _executar(context, () => _gestao.excluirCategoria(c));
    }
  }
}
