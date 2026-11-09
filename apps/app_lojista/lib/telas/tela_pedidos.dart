import 'dart:async';

import 'package:flutter/material.dart';

import '../modelos/pedido.dart';
import '../servicos/pedidos_servico.dart';
import '../servicos/whatsapp_servico.dart';
import '../tema.dart';
import '../util/formatar.dart';
import '../widgets/comum.dart';
import 'lista_rascunhos.dart';
import 'tela_detalhe_pedido.dart';

class _Aba {
  final String nome;
  final List<String> status;
  final bool whatsapp;
  const _Aba(this.nome, this.status, {this.whatsapp = false});
}

const _abaNovos = _Aba('Novos', ['novo']);
const _abaWhatsapp = _Aba('WhatsApp', [], whatsapp: true);
const _abasFixas = [
  _Aba('Preparo', ['aceito', 'em_preparo']),
  _Aba('Entrega', ['saiu_entrega']),
  _Aba('Concluídos', ['entregue', 'cancelado']),
];

/// Abas conforme os módulos da loja: "Novos" é do cardápio, "WhatsApp" dos rascunhos da IA
List<_Aba> _abasDaLoja(EmpresaLojista? e) => [
      if (e == null || e.moduloCardapio) _abaNovos,
      if (e != null && e.moduloWhatsapp) _abaWhatsapp,
      ..._abasFixas,
    ];

Color corStatus(String status, ColorScheme cores) => switch (status) {
      'novo' => Cores.primaria,
      'aceito' || 'em_preparo' => const Color(0xFFC2410C),
      'saiu_entrega' => const Color(0xFF6D28D9),
      'entregue' => Cores.sucesso,
      _ => const Color(0xFF5B5B66),
    };

/// Texto e ícone do botão do próximo passo
(String, IconData)? _acaoDoStatus(String status) => switch (status) {
      'novo' => ('Aceitar pedido', Icons.check_circle_outline),
      'aceito' => ('Começar preparo', Icons.soup_kitchen_outlined),
      'em_preparo' => ('Saiu para entrega', Icons.delivery_dining_outlined),
      'saiu_entrega' => ('Marcar como entregue', Icons.task_alt),
      _ => null,
    };

IconData _iconePagamento(String forma) => switch (forma) {
      'pix' => Icons.pix,
      'cartao' => Icons.credit_card,
      _ => Icons.payments_outlined,
    };

class TelaPedidos extends StatefulWidget {
  const TelaPedidos({super.key});

  @override
  State<TelaPedidos> createState() => _TelaPedidosState();
}

class _TelaPedidosState extends State<TelaPedidos> {
  final _servico = PedidosServico.instancia;
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    // atualiza "há X min" nos cartões
    _relogio = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final whatsapp = WhatsappServico.instancia;
    return ListenableBuilder(
      listenable: Listenable.merge([_servico, whatsapp]),
      builder: (context, _) {
        final empresa = _servico.empresa;
        final abas = _abasDaLoja(empresa);
        int quantidade(_Aba aba) => aba.whatsapp
            ? whatsapp.rascunhos.length
            : aba.nome == 'Concluídos'
                ? 0
                : _servico.pedidos.where((p) => aba.status.contains(p.statusPedido)).length;

        return DefaultTabController(
          key: ValueKey(abas.length),
          length: abas.length,
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Cabecalho(empresa: empresa, conectado: _servico.conectadoTempoReal),
                if (empresa != null) _CartaoLoja(empresa: empresa, aoAlternar: () => _confirmarAlternarLoja(empresa)),
                _AbasSegmentadas(abas: abas, quantidade: quantidade),
                if (_servico.erro != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Esp.m, 8, Esp.m, 0),
                    child: Material(
                      color: Cores.alertaClaro,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        leading: const Icon(Icons.wifi_off, color: Cores.alerta),
                        title: Text(_servico.erro!, style: const TextStyle(fontSize: 14)),
                        trailing: TextButton(onPressed: _servico.recarregar, child: const Text('Tentar')),
                      ),
                    ),
                  ),
                Expanded(
                  child: _servico.carregando && _servico.pedidos.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(children: [
                          for (final aba in abas)
                            if (aba.whatsapp)
                              const ListaRascunhos()
                            else
                              _ListaPedidos(
                                pedidos: _servico.pedidos.where((p) => aba.status.contains(p.statusPedido)).toList(),
                                aba: aba.nome,
                                lojaAberta: empresa?.abertaManual ?? true,
                              ),
                        ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmarAlternarLoja(EmpresaLojista empresa) async {
    final fechar = empresa.abertaManual;
    final ok = await confirmar(
      context,
      titulo: fechar ? 'Fechar a loja agora?' : 'Abrir a loja agora?',
      texto: fechar
          ? 'Os clientes não conseguem fazer pedidos até você abrir de novo.'
          : 'Os clientes passam a conseguir fazer pedidos pelo cardápio.',
      botao: fechar ? 'Fechar loja' : 'Abrir loja',
      perigo: fechar,
    );
    if (!ok) return;
    try {
      await _servico.alternarLoja();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }
}

/// Logo + nome da loja. O aviso de conexão só aparece quando há problema.
class _Cabecalho extends StatelessWidget {
  final EmpresaLojista? empresa;
  final bool conectado;
  const _Cabecalho({required this.empresa, required this.conectado});

  @override
  Widget build(BuildContext context) {
    final nome = empresa?.nomeEmpresa ?? 'Carregando...';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Esp.m, 12, Esp.m, 12),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Cores.primariaClara,
          backgroundImage: empresa?.logoUrl == null ? null : NetworkImage(empresa!.logoUrl!),
          child: empresa?.logoUrl == null
              ? Text(nome.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Cores.primaria))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(nome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Cores.texto)),
        ),
        if (!conectado && empresa != null)
          const Tooltip(
            message: 'Reconectando ao servidor',
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Cores.alerta)),
              SizedBox(width: 6),
              Text('Conectando', style: TextStyle(color: Cores.alerta, fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }
}

/// "Loja aberta" (verde) ou "Loja fechada" (vermelho) com o interruptor
class _CartaoLoja extends StatelessWidget {
  final EmpresaLojista empresa;
  final VoidCallback aoAlternar;
  const _CartaoLoja({required this.empresa, required this.aoAlternar});

  @override
  Widget build(BuildContext context) {
    final aberta = empresa.abertaManual;
    final cor = aberta ? Cores.sucesso : Cores.primaria;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Esp.m, 0, Esp.m, 14),
      child: Material(
        color: aberta ? const Color(0xFFF3FBF5) : Cores.primariaClara,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cor, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: aoAlternar,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(children: [
              Icon(aberta ? Icons.storefront : Icons.store_mall_directory_outlined, color: cor, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(aberta ? 'Loja aberta' : 'Loja fechada',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cor)),
                  if (!aberta)
                    const Text('Toque para abrir e receber pedidos',
                        style: TextStyle(fontSize: 14, color: Cores.textoSuave)),
                ]),
              ),
              Switch(value: aberta, onChanged: (_) => aoAlternar()),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Abas em forma de botões (como na proposta de design)
class _AbasSegmentadas extends StatelessWidget {
  final List<_Aba> abas;
  final int Function(_Aba) quantidade;
  const _AbasSegmentadas({required this.abas, required this.quantidade});

  @override
  Widget build(BuildContext context) {
    final rolar = abas.length > 4;
    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(Esp.m, 0, Esp.m, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Cores.borda),
      ),
      child: TabBar(
        isScrollable: rolar,
        tabAlignment: rolar ? TabAlignment.start : TabAlignment.fill,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Cores.primariaClara,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Cores.primaria, width: 1.5),
        ),
        splashBorderRadius: BorderRadius.circular(13),
        labelPadding: EdgeInsets.symmetric(horizontal: rolar ? 14 : 2),
        labelColor: Cores.primaria,
        unselectedLabelColor: Cores.texto,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        tabs: [
          for (final aba in abas)
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(aba.nome, overflow: TextOverflow.ellipsis)),
                if (quantidade(aba) > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Cores.primaria, borderRadius: BorderRadius.circular(11)),
                    child: Text('${quantidade(aba)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

class _ListaPedidos extends StatelessWidget {
  final List<Pedido> pedidos;
  final String aba;
  final bool lojaAberta;
  const _ListaPedidos({required this.pedidos, required this.aba, required this.lojaAberta});

  @override
  Widget build(BuildContext context) {
    final servico = PedidosServico.instancia;
    if (pedidos.isEmpty) {
      final (icone, texto) = switch (aba) {
        'Novos' when !lojaAberta => (Icons.store_mall_directory_outlined, 'Sua loja está fechada.\nAbra no botão acima para receber pedidos.'),
        'Novos' => (Icons.notifications_active_outlined, 'Nenhum pedido novo.\nQuando chegar, o celular toca um alarme.'),
        'Preparo' => (Icons.soup_kitchen_outlined, 'Nada sendo preparado.'),
        'Entrega' => (Icons.delivery_dining_outlined, 'Nenhum pedido saiu para entrega.'),
        _ => (Icons.task_alt, 'Os pedidos entregues aparecem aqui.'),
      };
      return RefreshIndicator(
        onRefresh: servico.recarregar,
        child: ListView(children: [const SizedBox(height: 60), EstadoVazio(icone: icone, texto: texto)]),
      );
    }
    return RefreshIndicator(
      onRefresh: servico.recarregar,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(Esp.m, 12, Esp.m, Esp.g),
        itemCount: pedidos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, i) => _CartaoPedido(key: ValueKey(pedidos[i].id), pedido: pedidos[i]),
      ),
    );
  }
}

class _CartaoPedido extends StatefulWidget {
  final Pedido pedido;
  const _CartaoPedido({super.key, required this.pedido});

  @override
  State<_CartaoPedido> createState() => _CartaoPedidoState();
}

class _CartaoPedidoState extends State<_CartaoPedido> {
  bool _enviando = false;

  Future<void> _avancar(String proximo) async {
    setState(() => _enviando = true);
    try {
      await PedidosServico.instancia.mudarStatus(widget.pedido, proximo);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pedido;
    final minutos = DateTime.now().difference(p.criadoEm).inMinutes;
    final novo = p.statusPedido == 'novo';
    final etapa = p.proximaEtapa;
    final acao = _acaoDoStatus(p.statusPedido);
    final atrasado = !p.finalizado && minutos >= 40;
    // troco já calculado (pedido do 1º cliente real)
    final pagamento = p.formaPagamento == 'dinheiro' && p.trocoPara != null && p.trocoPara! > p.valorTotal
        ? 'Dinheiro · levar troco ${formatarMoeda(p.trocoPara! - p.valorTotal)}'
        : nomesPagamento[p.formaPagamento] ?? p.formaPagamento;
    final itens = p.itens.take(4).toList();

    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: novo ? Cores.primariaBorda : Cores.borda, width: novo ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDetalhePedido(idPedido: p.id))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // número, cliente e tempo
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: Cores.primariaClara, shape: BoxShape.circle),
                child: Icon(p.origemPedido == 'whatsapp' ? Icons.chat_outlined : Icons.receipt_long_outlined,
                    color: Cores.primaria, size: 22),
              ),
              const SizedBox(width: 12),
              Text('#${p.numeroPedido}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(p.nomeCliente,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.schedule, size: 18, color: atrasado ? Cores.primaria : Cores.textoSuave),
              const SizedBox(width: 4),
              Text(minutos < 60 ? 'há $minutos min' : 'há ${minutos ~/ 60}h',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: atrasado ? FontWeight.w700 : FontWeight.w500,
                    color: atrasado ? Cores.primaria : Cores.textoSuave,
                  )),
            ]),
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
            // itens | total
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final item in itens)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: const BoxDecoration(color: Cores.primaria, shape: BoxShape.circle),
                          ),
                          Expanded(
                            child: Text('${item.quantidade}x ${item.nomeProduto}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 17)),
                          ),
                        ]),
                      ),
                    if (p.itens.length > itens.length)
                      Text('+ ${p.itens.length - itens.length} itens',
                          style: const TextStyle(color: Cores.textoSuave, fontSize: 15)),
                  ]),
                ),
                const VerticalDivider(width: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    FittedBox(
                      child: Text(formatarMoeda(p.valorTotal),
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_iconePagamento(p.formaPagamento), size: 16, color: Cores.textoSuave),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(pagamento,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 14, color: Cores.textoSuave)),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (etapa != null && acao != null)
              _botaoAcao(acao, etapa.$1, principal: novo)
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: corStatus(p.statusPedido, Theme.of(context).colorScheme).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(nomesStatus[p.statusPedido] ?? p.statusPedido,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: corStatus(p.statusPedido, Theme.of(context).colorScheme),
                      )),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// Aceitar = botão cheio (é o mais importante). Os passos seguintes = botão claro.
  Widget _botaoAcao((String, IconData) acao, String proximo, {required bool principal}) {
    final carregando = _enviando
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: principal ? Colors.white : Cores.primaria),
          )
        : Icon(acao.$2, size: 24);
    final texto = Text(acao.$1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));
    final aoTocar = _enviando ? null : () => _avancar(proximo);
    return principal
        ? FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: aoTocar,
            icon: carregando,
            label: texto,
          )
        : FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: Cores.primariaClara,
              foregroundColor: Cores.primaria,
            ),
            onPressed: aoTocar,
            icon: carregando,
            label: texto,
          );
  }
}
