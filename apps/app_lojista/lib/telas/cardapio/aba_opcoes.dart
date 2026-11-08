import 'package:flutter/material.dart';

import '../../modelos/gestao.dart';
import '../../servicos/gestao_servico.dart';
import '../../tema.dart';
import '../../util/formatar.dart';
import '../../widgets/comum.dart';

/// Atalhos para os grupos mais comuns de lanchonete
const _modelos = [('Escolha o pão', 1, 1), ('Adicionais', 0, 10), ('Ponto da carne', 1, 1), ('Molhos', 0, 2)];

/// Grupos de opções reutilizáveis (ex.: "Escolha o pão" obrigatório, "Adicionais" opcional)
class AbaOpcoes extends StatelessWidget {
  final bool ordenando;
  final Future<void> Function() aoAtualizar;
  const AbaOpcoes({super.key, required this.ordenando, required this.aoAtualizar});

  GestaoServico get _gestao => GestaoServico.instancia;

  @override
  Widget build(BuildContext context) {
    final grupos = _gestao.grupos;
    final nomes = grupos.map((g) => g.nomeGrupo.toLowerCase()).toSet();
    final atalhos = _modelos.where((m) => !nomes.contains(m.$1.toLowerCase())).toList();

    return RefreshIndicator(
      onRefresh: aoAtualizar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Esp.m, Esp.m, Esp.m, 40),
        children: [
          const Dica(
            'Crie cada grupo uma vez e use em vários produtos. Ex.: "Escolha o pão" (o cliente escolhe 1) '
            'ou "Adicionais" (bacon, ovo, cheddar...).',
          ),
          if (atalhos.isNotEmpty && !ordenando) ...[
            const Text('Criar rápido:', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in atalhos)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(m.$1),
                    onPressed: () => _executar(context, () => _gestao.criarGrupo(m.$1, minimo: m.$2, maximo: m.$3)),
                  ),
              ],
            ),
            const SizedBox(height: Esp.m),
          ],
          for (var i = 0; i < grupos.length; i++)
            _CartaoGrupo(grupos: grupos, indice: i, ordenando: ordenando, executar: _executar),
          if (!ordenando)
            OutlinedButton.icon(
              onPressed: () async {
                final nome = await pedirTexto(
                  context,
                  titulo: 'Novo grupo',
                  rotulo: 'Ex.: Escolha a bebida',
                  botao: 'Criar',
                );
                if (nome != null && context.mounted) await _executar(context, () => _gestao.criarGrupo(nome));
              },
              icon: const Icon(Icons.add),
              label: const Text('Novo grupo'),
            ),
        ],
      ),
    );
  }

  static Future<void> _executar(BuildContext context, Future<void> Function() acao) async {
    try {
      await acao();
    } catch (e) {
      if (context.mounted) mostrarErro(context, e);
    }
  }
}

class _CartaoGrupo extends StatelessWidget {
  final List<GrupoOpcoes> grupos;
  final int indice;
  final bool ordenando;
  final Future<void> Function(BuildContext, Future<void> Function()) executar;
  const _CartaoGrupo({required this.grupos, required this.indice, required this.ordenando, required this.executar});

  GestaoServico get _gestao => GestaoServico.instancia;

  @override
  Widget build(BuildContext context) {
    final g = grupos[indice];
    final cores = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: Esp.m),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.nomeGrupo,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: g.ativo ? null : cores.outline,
                        ),
                      ),
                      Text(
                        g.ativo ? g.regra : '${g.regra} · escondido',
                        style: const TextStyle(fontSize: 14, color: Cores.textoSuave),
                      ),
                    ],
                  ),
                ),
                if (ordenando)
                  BotoesOrdem(
                    aoSubir: indice > 0
                        ? () => executar(context, () => _gestao.mover('grupos_opcoes', grupos, indice, -1))
                        : null,
                    aoDescer: indice < grupos.length - 1
                        ? () => executar(context, () => _gestao.mover('grupos_opcoes', grupos, indice, 1))
                        : null,
                  )
                else
                  PopupMenuButton<String>(
                    tooltip: 'Editar grupo',
                    icon: const Icon(Icons.edit_outlined),
                    onSelected: (v) => _acao(context, g, v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'renomear', child: Text('Renomear')),
                      PopupMenuItem(
                        value: 'ativo',
                        child: Text(g.ativo ? 'Esconder do cardápio' : 'Mostrar no cardápio'),
                      ),
                      const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                    ],
                  ),
              ],
            ),
          ),
          if (!ordenando)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(color: Cores.fundo, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Cliente é obrigado a escolher', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Switch(
                        value: g.obrigatorio,
                        onChanged: (v) => executar(context, () => _gestao.atualizarGrupo(g, obrigatorio: v)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Pode escolher até', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: 'Menos',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: g.maximoSelecao > 1
                            ? () => executar(context, () => _gestao.atualizarGrupo(g, maximo: g.maximoSelecao - 1))
                            : null,
                      ),
                      Text('${g.maximoSelecao}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        tooltip: 'Mais',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: g.maximoSelecao < 50
                            ? () => executar(context, () => _gestao.atualizarGrupo(g, maximo: g.maximoSelecao + 1))
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (g.opcoes.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Nenhuma opção ainda. Ex.: Bacon, Pão australiano...',
                style: TextStyle(color: Cores.textoSuave),
              ),
            ),
          for (var j = 0; j < g.opcoes.length; j++) _linhaOpcao(context, g, j),
          if (!ordenando)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: OutlinedButton.icon(
                onPressed: () => _editarOpcao(context, g),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar opção'),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _linhaOpcao(BuildContext context, GrupoOpcoes g, int indice) {
    final o = g.opcoes[indice];
    final cores = Theme.of(context).colorScheme;
    return ListTile(
      key: ValueKey(o.id),
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      title: Text(o.nomeOpcao, style: TextStyle(color: o.ativo ? null : cores.outline)),
      subtitle: Text(o.precoAdicional > 0 ? '+ ${formatarMoeda(o.precoAdicional)}' : 'Sem custo extra'),
      onTap: ordenando ? null : () => _editarOpcao(context, g, o),
      trailing: ordenando
          ? BotoesOrdem(
              aoSubir: indice > 0 ? () => executar(context, () => _gestao.mover('opcoes', g.opcoes, indice, -1)) : null,
              aoDescer: indice < g.opcoes.length - 1
                  ? () => executar(context, () => _gestao.mover('opcoes', g.opcoes, indice, 1))
                  : null,
            )
          : InterruptorRotulado(
              valor: o.ativo,
              ligado: 'Tem',
              desligado: 'Em falta',
              aoMudar: (_) => executar(context, () => _gestao.alternarOpcao(o)),
            ),
    );
  }

  Future<void> _acao(BuildContext context, GrupoOpcoes g, String acao) async {
    switch (acao) {
      case 'renomear':
        final nome = await pedirTexto(context, titulo: 'Renomear grupo', inicial: g.nomeGrupo);
        if (nome != null && context.mounted) await executar(context, () => _gestao.atualizarGrupo(g, nome: nome));
      case 'ativo':
        await executar(context, () => _gestao.alternarGrupo(g));
      case 'excluir':
        final ok = await confirmar(
          context,
          titulo: 'Excluir "${g.nomeGrupo}"?',
          texto: 'O grupo e as opções saem de todos os produtos que usam ele.',
          botao: 'Excluir',
          perigo: true,
        );
        if (ok && context.mounted) await executar(context, () => _gestao.excluirGrupo(g));
    }
  }

  /// Diálogo de nome + preço. Sem [opcao] cria uma nova.
  Future<void> _editarOpcao(BuildContext context, GrupoOpcoes g, [Opcao? opcao]) async {
    final nome = TextEditingController(text: opcao?.nomeOpcao);
    final preco = TextEditingController(
      text: opcao == null || opcao.precoAdicional == 0 ? '' : numeroParaCampo(opcao.precoAdicional),
    );
    final resultado = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(opcao == null ? 'Nova opção em "${g.nomeGrupo}"' : 'Editar opção'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nome,
              autofocus: opcao == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex.: Bacon',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            CampoMoeda(controle: preco, rotulo: 'Preço adicional (vazio = sem custo)'),
          ],
        ),
        actions: [
          if (opcao != null)
            TextButton(
              onPressed: () => Navigator.pop(c, 'excluir'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
              child: const Text('Excluir'),
            ),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, 'salvar'), child: const Text('Salvar')),
        ],
      ),
    );
    if (!context.mounted) return;
    final texto = nome.text.trim();
    if (resultado == 'excluir' && opcao != null) {
      await executar(context, () => _gestao.excluirOpcao(g, opcao));
    } else if (resultado == 'salvar' && texto.isNotEmpty) {
      final valor = lerNumero(preco.text.isEmpty ? '0' : preco.text);
      await executar(
        context,
        () => opcao == null
            ? _gestao.criarOpcao(g, texto, valor)
            : _gestao.atualizarOpcao(opcao, nome: texto, preco: valor),
      );
    }
  }
}
