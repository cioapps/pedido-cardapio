import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../modelos/pedido.dart';
import '../servicos/pedidos_servico.dart';
import '../util/formatar.dart';
import 'tela_pedidos.dart' show corStatus;

class TelaDetalhePedido extends StatefulWidget {
  final int idPedido;
  const TelaDetalhePedido({super.key, required this.idPedido});

  @override
  State<TelaDetalhePedido> createState() => _TelaDetalhePedidoState();
}

class _TelaDetalhePedidoState extends State<TelaDetalhePedido> {
  final _servico = PedidosServico.instancia;
  bool _ocupado = false;

  Future<void> _executar(Future<void> Function() acao, {String? sucesso}) async {
    setState(() => _ocupado = true);
    final mensageiro = ScaffoldMessenger.of(context);
    try {
      await acao();
      if (sucesso != null) mensageiro.showSnackBar(SnackBar(content: Text(sucesso)));
    } catch (e) {
      mensageiro.showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _cancelar(Pedido p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Cancelar pedido #${p.numeroPedido}?'),
        content: const Text('Avise o cliente pelo WhatsApp sobre o cancelamento.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (ok == true) await _executar(() => _servico.mudarStatus(p, 'cancelado'));
  }

  void _abrirWhatsApp(Pedido p) {
    var tel = p.telefoneCliente.replaceAll(RegExp(r'\D'), '');
    if (tel.length <= 11) tel = '55$tel';
    final texto = Uri.encodeComponent('Olá, ${p.nomeCliente}! Sobre o seu pedido #${p.numeroPedido}: ');
    launchUrl(Uri.parse('https://wa.me/$tel?text=$texto'), mode: LaunchMode.externalApplication);
  }

  void _abrirMapa(Pedido p) {
    final q = Uri.encodeComponent('${p.enderecoCompleto}, ${p.nomeBairro}');
    launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _servico,
      builder: (context, _) {
        final p = _servico.pedidos.where((x) => x.id == widget.idPedido).firstOrNull;
        if (p == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Pedido não encontrado')));
        }
        final proxima = p.proximaEtapa;
        final titulo = Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold);

        return Scaffold(
          appBar: AppBar(
            title: Text('Pedido #${p.numeroPedido}'),
            actions: [
              IconButton(
                tooltip: 'Imprimir',
                icon: const Icon(Icons.print),
                onPressed: _ocupado ? null : () => _executar(() => _servico.imprimir(p), sucesso: 'Enviado para a impressora'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: corStatus(p.statusPedido, Theme.of(context).colorScheme),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(nomesStatus[p.statusPedido] ?? '',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                Text(formatarDataHora(p.criadoEm), style: TextStyle(color: Colors.grey.shade700)),
                const Spacer(),
                if (p.impresso) const Chip(avatar: Icon(Icons.print, size: 16), label: Text('Impresso')),
              ]),
              const SizedBox(height: 16),
              Text('Itens', style: titulo),
              const SizedBox(height: 4),
              for (final item in p.itens)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${item.quantidade}x ', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.nomeProduto, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        for (final o in item.opcoes)
                          Text('${o.nomeGrupo}: ${o.descricao}', style: TextStyle(color: Colors.grey.shade800)),
                        if (item.observacaoItem?.isNotEmpty ?? false)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            color: Colors.amber.shade100,
                            child: Text('Obs.: ${item.observacaoItem}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                      ]),
                    ),
                    Text(formatarMoeda(item.valorTotalItem)),
                  ]),
                ),
              if (p.observacaoPedido?.isNotEmpty ?? false)
                Card(
                  color: Colors.amber.shade100,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Observação do pedido: ${p.observacaoPedido}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              const Divider(height: 28),
              _linha('Subtotal', formatarMoeda(p.subtotal)),
              _linha('Entrega', formatarMoeda(p.taxaEntrega)),
              _linha('Total', formatarMoeda(p.valorTotal), negrito: true),
              const SizedBox(height: 6),
              _linha('Pagamento', nomesPagamento[p.formaPagamento] ?? p.formaPagamento),
              if (p.trocoPara != null) ...[
                _linha('Troco para', formatarMoeda(p.trocoPara)),
                _linha('Levar de troco', formatarMoeda(p.trocoPara! - p.valorTotal), negrito: true),
              ],
              const Divider(height: 28),
              Text('Entrega', style: titulo),
              const SizedBox(height: 6),
              Text(p.nomeCliente, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              Text(formatarTelefone(p.telefoneCliente)),
              const SizedBox(height: 4),
              Text('${p.enderecoCompleto}\n${p.nomeBairro}'),
              if (p.pontoReferencia?.isNotEmpty ?? false) Text('Ref.: ${p.pontoReferencia}'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => _abrirWhatsApp(p),
                  icon: const Icon(Icons.chat),
                  label: const Text('WhatsApp'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _abrirMapa(p),
                  icon: const Icon(Icons.map),
                  label: const Text('Mapa'),
                ),
              ]),
              if (!p.finalizado) ...[
                const SizedBox(height: 24),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: _ocupado ? null : () => _cancelar(p),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar pedido'),
                ),
              ],
            ],
          ),
          bottomNavigationBar: proxima == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: p.statusPedido == 'novo' ? Colors.green.shade700 : null,
                      ),
                      onPressed: _ocupado ? null : () => _executar(() => _servico.mudarStatus(p, proxima.$1)),
                      child: Text(proxima.$2, style: const TextStyle(fontSize: 17)),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _linha(String rotulo, String valor, {bool negrito = false}) {
    final estilo = TextStyle(fontSize: negrito ? 17 : 15, fontWeight: negrito ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Text(rotulo, style: estilo), const Spacer(), Text(valor, style: estilo)]),
    );
  }
}
