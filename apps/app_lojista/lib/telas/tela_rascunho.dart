import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../modelos/rascunho.dart';
import '../servicos/whatsapp_servico.dart';
import '../util/formatar.dart';

/// Revisão do pedido que a IA montou a partir da conversa
class TelaRascunho extends StatefulWidget {
  final Rascunho rascunho;
  const TelaRascunho({super.key, required this.rascunho});

  @override
  State<TelaRascunho> createState() => _TelaRascunhoState();
}

class _TelaRascunhoState extends State<TelaRascunho> {
  final _servico = WhatsappServico.instancia;
  late final DadosRascunho _dados = DadosRascunho.fromJson(widget.rascunho.dados.toJson());
  late final _nome = TextEditingController(text: _dados.nomeCliente);
  late final _rua = TextEditingController(text: _dados.logradouro);
  late final _numero = TextEditingController(text: _dados.numeroEndereco);
  late final _complemento = TextEditingController(text: _dados.complemento);
  late final _referencia = TextEditingController(text: _dados.pontoReferencia);
  late final _troco = TextEditingController(text: _dados.trocoPara?.toStringAsFixed(2).replaceAll('.', ',') ?? '');
  late final _obs = TextEditingController(text: _dados.observacaoPedido);
  late final Future<List<MensagemWhatsapp>> _mensagens = _servico.mensagens(widget.rascunho.idConversa);
  bool _enviando = false;

  Rascunho get r => widget.rascunho;
  CardapioResumo? get cardapio => _servico.cardapio;

  void _sincronizar() {
    _dados
      ..nomeCliente = _nome.text
      ..logradouro = _rua.text
      ..numeroEndereco = _numero.text
      ..complemento = _complemento.text
      ..pontoReferencia = _referencia.text
      ..observacaoPedido = _obs.text
      ..trocoPara = double.tryParse(_troco.text.replaceAll('.', '').replaceAll(',', '.'));
  }

  Future<void> _confirmar() async {
    _sincronizar();
    final mensageiro = ScaffoldMessenger.of(context);
    final navegador = Navigator.of(context);
    setState(() => _enviando = true);
    try {
      final numero = await _servico.confirmar(r, _dados);
      mensageiro.showSnackBar(SnackBar(content: Text('Pedido #$numero confirmado')));
      navegador.pop();
    } catch (e) {
      mensageiro.showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(_mensagemErro(e)),
      ));
    }
    if (mounted) setState(() => _enviando = false);
  }

  String _mensagemErro(Object e) =>
      e is PostgrestException ? e.message : '$e'.replaceFirst('Exception: ', '');

  Future<void> _descartar({required bool ignorar}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(ignorar ? 'Ignorar este contato?' : 'Descartar este pedido?'),
        content: Text(ignorar
            ? 'A IA deixa de acompanhar as conversas deste contato (fornecedor, amigo, etc.).'
            : 'A IA volta a montar um pedido novo se o cliente continuar pedindo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ignorar ? 'Ignorar' : 'Descartar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navegador = Navigator.of(context);
    await _servico.descartar(r, ignorarContato: ignorar);
    navegador.pop();
  }

  @override
  Widget build(BuildContext context) {
    final cardapio = this.cardapio;
    final titulo = Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold);
    final total = cardapio?.total(_dados) ?? r.valorEstimado;

    return Scaffold(
      appBar: AppBar(
        title: Text(r.titulo),
        actions: [
          if (r.telefoneContato != null)
            IconButton(
              tooltip: 'Abrir conversa',
              icon: const Icon(Icons.chat),
              onPressed: () => launchUrl(Uri.parse('https://wa.me/${r.telefoneContato}'), mode: LaunchMode.externalApplication),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => _descartar(ignorar: v == 'ignorar'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'descartar', child: Text('Descartar pedido')),
              PopupMenuItem(value: 'ignorar', child: Text('Ignorar este contato')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          if (r.resumoIa != null && r.resumoIa!.isNotEmpty)
            Text(r.resumoIa!, style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
          if (r.pendencias.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Falta definir', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final p in r.pendencias) Text('• $p'),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Text('Itens', style: titulo),
          if (_dados.itens.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('A IA ainda não identificou itens. Continue a conversa com o cliente.'),
            ),
          for (final item in _dados.itens) _linhaItem(item, cardapio),
          const Divider(height: 28),
          Text('Entrega', style: titulo),
          const SizedBox(height: 8),
          _campo(_nome, 'Nome do cliente'),
          Row(children: [
            Expanded(flex: 3, child: _campo(_rua, 'Rua')),
            const SizedBox(width: 8),
            Expanded(child: _campo(_numero, 'Nº')),
          ]),
          _campo(_complemento, 'Complemento'),
          _campo(_referencia, 'Ponto de referência'),
          if (cardapio != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<int>(
                initialValue: cardapio.bairros.any((b) => b.id == _dados.idBairroEntrega) ? _dados.idBairroEntrega : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bairro', border: OutlineInputBorder()),
                items: [
                  for (final b in cardapio.bairros)
                    DropdownMenuItem(value: b.id, child: Text('${b.nome} — ${formatarMoeda(b.taxa)}')),
                ],
                onChanged: (v) => setState(() => _dados.idBairroEntrega = v),
              ),
            ),
          const SizedBox(height: 4),
          Text('Pagamento', style: titulo),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'pix', label: Text('Pix')),
              ButtonSegment(value: 'cartao', label: Text('Cartão')),
              ButtonSegment(value: 'dinheiro', label: Text('Dinheiro')),
            ],
            selected: {?_dados.formaPagamento},
            onSelectionChanged: (s) => setState(() => _dados.formaPagamento = s.firstOrNull),
          ),
          if (_dados.formaPagamento == 'dinheiro') ...[
            const SizedBox(height: 10),
            _campo(_troco, 'Troco para (R\$)', teclado: const TextInputType.numberWithOptions(decimal: true)),
          ],
          _campo(_obs, 'Observação do pedido'),
          const Divider(height: 28),
          Row(children: [
            Text('Total', style: titulo),
            const Spacer(),
            Text(formatarMoeda(total), style: titulo),
          ]),
          const Divider(height: 28),
          Text('Conversa', style: titulo),
          const SizedBox(height: 8),
          FutureBuilder<List<MensagemWhatsapp>>(
            future: _mensagens,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return Column(children: [for (final m in snap.data!) _balao(m)]);
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: Colors.green.shade700),
            onPressed: _enviando || _dados.itens.isEmpty ? null : _confirmar,
            icon: const Icon(Icons.check),
            label: Text(_enviando ? 'Confirmando...' : 'Confirmar e imprimir', style: const TextStyle(fontSize: 17)),
          ),
        ),
      ),
    );
  }

  Widget _linhaItem(ItemRascunho item, CardapioResumo? cardapio) {
    final produto = cardapio?.produtos[item.idProduto];
    final opcoes = item.opcoes.map((o) {
      final op = cardapio?.opcoes[o.idOpcao];
      return op == null ? '?' : '${o.quantidade > 1 ? '${o.quantidade}x ' : ''}${op.nome}';
    }).join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(produto?.nome ?? 'Produto removido do cardápio',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (opcoes.isNotEmpty) Text(opcoes, style: TextStyle(color: Colors.grey.shade700)),
            if (item.observacaoItem.isNotEmpty)
              Text('Obs.: ${item.observacaoItem}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (cardapio != null) Text(formatarMoeda(cardapio.precoItem(item))),
          ]),
        ),
        IconButton(
          icon: Icon(item.quantidade == 1 ? Icons.delete_outline : Icons.remove_circle_outline),
          onPressed: () => setState(() {
            if (item.quantidade == 1) {
              _dados.itens.remove(item);
            } else {
              item.quantidade--;
            }
          }),
        ),
        Text('${item.quantidade}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: item.quantidade < 99 ? () => setState(() => item.quantidade++) : null,
        ),
      ]),
    );
  }

  Widget _campo(TextEditingController c, String rotulo, {TextInputType? teclado}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: teclado,
          decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  Widget _balao(MensagemWhatsapp m) {
    final loja = m.enviadaPelaLoja;
    return Align(
      alignment: loja ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: loja ? const Color(0xFFD9FDD3) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(m.texto),
          Text(formatarHora(m.enviadaEm), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_nome, _rua, _numero, _complemento, _referencia, _troco, _obs]) {
      c.dispose();
    }
    super.dispose();
  }
}
