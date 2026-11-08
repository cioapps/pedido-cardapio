import 'package:flutter/material.dart';

import '../modelos/rascunho.dart';
import '../servicos/whatsapp_servico.dart';
import '../util/formatar.dart';
import 'tela_rascunho.dart';

/// Aba "WhatsApp": pedidos que a IA está montando a partir das conversas
class ListaRascunhos extends StatelessWidget {
  const ListaRascunhos({super.key});

  @override
  Widget build(BuildContext context) {
    final servico = WhatsappServico.instancia;
    final lista = servico.rascunhos;
    if (lista.isEmpty) {
      return RefreshIndicator(
        onRefresh: servico.recarregar,
        child: ListView(children: [
          const SizedBox(height: 120),
          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            servico.erro ??
                'Nenhum pedido em andamento no WhatsApp.\nConverse normalmente com o cliente: a IA monta o pedido aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ]),
      );
    }
    // prontos primeiro
    final ordenada = [...lista]..sort((a, b) => (b.pronto ? 1 : 0) - (a.pronto ? 1 : 0));
    return RefreshIndicator(
      onRefresh: servico.recarregar,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: ordenada.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _CartaoRascunho(rascunho: ordenada[i]),
      ),
    );
  }
}

class _CartaoRascunho extends StatelessWidget {
  final Rascunho rascunho;
  const _CartaoRascunho({required this.rascunho});

  @override
  Widget build(BuildContext context) {
    final r = rascunho;
    final cardapio = WhatsappServico.instancia.cardapio;
    final cores = Theme.of(context).colorScheme;
    final itens = r.dados.itens
        .map((i) => '${i.quantidade}x ${cardapio?.produtos[i.idProduto]?.nome ?? '?'}')
        .join(', ');

    return Card(
      elevation: 0,
      color: r.pronto ? Colors.green.shade50 : cores.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: r.pronto ? Colors.green.shade400 : cores.outlineVariant, width: r.pronto ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaRascunho(rascunho: r))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.chat, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.titulo,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: r.pronto ? Colors.green.shade700 : Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(r.pronto ? 'Pronto' : 'Montando…',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(itens.isEmpty ? 'Ainda sem itens' : itens, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (r.pendencias.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.amber.shade100,
                child: Text(r.pendencias.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Text(formatarMoeda(cardapio?.total(r.dados) ?? r.valorEstimado),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('atualizado ${formatarHora(r.atualizadoEm)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ]),
          ]),
        ),
      ),
    );
  }
}
