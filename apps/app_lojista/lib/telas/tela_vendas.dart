import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tema.dart';
import '../util/formatar.dart';
import '../widgets/comum.dart';
import 'vendas/escolher_periodo.dart';
import 'vendas/periodo.dart';

double _n(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

/// Aba Vendas: quanto a loja vendeu no período escolhido (dados de resumo_vendas no banco)
class TelaVendas extends StatefulWidget {
  const TelaVendas({super.key});

  /// A tela principal avisa quando a aba é aberta, para atualizar os números
  static final atualizar = ValueNotifier<int>(0);

  @override
  State<TelaVendas> createState() => _TelaVendasState();
}

class _TelaVendasState extends State<TelaVendas> {
  // abre em "Este mês"
  Periodo _periodo = Periodo.atalhos().firstWhere((p) => p.atalho == 'Este mês');
  Map<String, dynamic>? _dados;
  String? _erro;
  bool _carregando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
    TelaVendas.atualizar.addListener(_aoAbrirAba);
  }

  @override
  void dispose() {
    TelaVendas.atualizar.removeListener(_aoAbrirAba);
    super.dispose();
  }

  /// Ao voltar para a aba: se o período era um atalho (ex.: "Hoje"), recalcula as datas (pode ter virado o dia)
  void _aoAbrirAba() {
    final atalho = _periodo.atalho;
    if (atalho != null) _periodo = Periodo.atalhos().firstWhere((p) => p.atalho == atalho);
    _carregar();
  }

  Future<void> _carregar() async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    final f = DateFormat('yyyy-MM-dd');
    try {
      final r = await Supabase.instance.client.rpc(
        'resumo_vendas',
        params: {'p_inicio': f.format(_periodo.inicio), 'p_fim': f.format(_periodo.fim)},
      );
      if (mounted) setState(() => _dados = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErro(e));
    }
    if (mounted) setState(() => _carregando = false);
  }

  void _mudar(Periodo p) {
    setState(() => _periodo = p);
    _carregar();
  }

  Future<void> _abrirSeletor() async {
    final p = await escolherPeriodo(context, _periodo);
    if (p != null) _mudar(p);
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    const rapidos = ['Hoje', 'Ontem', '7 dias', 'Este mês', 'Mês passado'];
    final atalhos = Periodo.atalhos().where((a) => rapidos.contains(a.atalho)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Vendas')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Esp.m, 4, Esp.m, 12),
              child: _SeletorPeriodo(periodo: _periodo, aoTocar: _abrirSeletor),
            ),
            // atalhos rápidos (rolam para o lado)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Esp.m),
                itemCount: atalhos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final a = atalhos[i];
                  final sel = a.mesmoQue(_periodo);
                  return Material(
                    color: sel ? Cores.primariaClara : Colors.white,
                    shape: StadiumBorder(
                      side: BorderSide(color: sel ? Cores.primaria : Cores.borda, width: sel ? 1.5 : 1),
                    ),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => _mudar(a),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Center(
                          child: Text(
                            a.atalho!,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                              color: sel ? Cores.primaria : Cores.texto,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Esp.m),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Esp.m),
              child: _erro != null
                  ? EstadoVazio(
                      icone: Icons.wifi_off,
                      texto: _erro!,
                      acao: FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                    )
                  : d == null
                  ? const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : AnimatedOpacity(
                      opacity: _carregando ? 0.5 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: _Conteudo(dados: d, periodo: _periodo),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão grande com o período atual; abre a janela "Escolher período"
class _SeletorPeriodo extends StatelessWidget {
  final Periodo periodo;
  final VoidCallback aoTocar;
  const _SeletorPeriodo({required this.periodo, required this.aoTocar});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Cores.borda),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, size: 30, color: Cores.texto),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(periodo.titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(periodo.subtitulo, style: const TextStyle(fontSize: 14, color: Cores.textoSuave)),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 28, color: Cores.textoSuave),
          ],
        ),
      ),
    ),
  );
}

class _Conteudo extends StatelessWidget {
  final Map<String, dynamic> dados;
  final Periodo periodo;
  const _Conteudo({required this.dados, required this.periodo});

  @override
  Widget build(BuildContext context) {
    final faturamento = _n(dados['faturamento']);
    final anterior = _n(dados['faturamento_anterior']);
    final pedidos = (dados['pedidos'] as num?)?.toInt() ?? 0;
    final ticket = _n(dados['ticket_medio']);
    final cancelados = (dados['cancelados'] as num?)?.toInt() ?? 0;
    final variacao = anterior > 0 ? (faturamento - anterior) / anterior * 100 : null;
    final porDia = ((dados['por_dia'] as List?) ?? []).cast<Map>();
    final porHora = ((dados['por_hora'] as List?) ?? []).cast<Map>();
    final mais = ((dados['mais_vendidos'] as List?) ?? []).cast<Map>();
    final pagamentos = ((dados['por_pagamento'] as List?) ?? []).cast<Map>();

    if (pedidos == 0 && cancelados == 0) {
      return EstadoVazio(
        icone: Icons.bar_chart,
        texto: periodo.atalho == 'Hoje'
            ? 'Nenhuma venda hoje ainda.\nOs números aparecem aqui assim que chegar o primeiro pedido.'
            : 'Nenhuma venda neste período.\nTente escolher outras datas.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Esp.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Faturamento',
                  style: TextStyle(fontSize: 16, color: Cores.textoSuave, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  child: Text(
                    formatarMoeda(faturamento),
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
                  ),
                ),
                if (variacao != null) ...[
                  const SizedBox(height: 6),
                  _PilulaVariacao(variacao: variacao, comparado: periodo.rotuloAnterior),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Numero(rotulo: 'Pedidos', valor: '$pedidos'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Numero(rotulo: 'Ticket médio', valor: formatarMoeda(ticket)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (periodo.umDia)
          _Secao(
            titulo: 'Pedidos por horário',
            child: _Barras(
              valores: [for (final h in porHora) _n(h['pedidos'])],
              rotulos: [for (final h in porHora) '${h['hora']}h'],
              dicas: [
                for (final h in porHora) '${h['hora']}h · ${h['pedidos']} ${h['pedidos'] == 1 ? 'pedido' : 'pedidos'}',
              ],
            ),
          )
        else
          _Secao(
            titulo: 'Vendas por dia',
            child: _Barras(
              valores: [for (final d in porDia) _n(d['faturamento'])],
              rotulos: [for (final d in porDia) '${DateTime.parse('${d['dia']}').day}'],
              dicas: [
                for (final d in porDia)
                  () {
                    final dia = DateTime.parse('${d['dia']}');
                    return '${diasSemanaCurtos[dia.weekday % 7]} ${dia.day} · ${formatarMoeda(_n(d['faturamento']))}';
                  }(),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (mais.isNotEmpty)
          _Secao(
            titulo: 'Mais vendidos',
            child: Column(
              children: [
                for (var i = 0; i < mais.length; i++) ...[
                  if (i > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: Cores.primariaClara,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Cores.primaria),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${mais[i]['nome']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text('${mais[i]['quantidade']} un.', style: const TextStyle(color: Cores.textoSuave)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 96,
                          child: Text(
                            formatarMoeda(_n(mais[i]['valor'])),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (pagamentos.isNotEmpty)
          _Secao(
            titulo: 'Formas de pagamento',
            child: Column(
              children: [
                for (final p in pagamentos)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                nomesPagamento[p['forma']] ?? '${p['forma']}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(formatarMoeda(_n(p['valor'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: faturamento > 0 ? _n(p['valor']) / faturamento : 0,
                            minHeight: 8,
                            backgroundColor: Cores.fundo,
                            color: Cores.primaria,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          [
            'Inclui ${formatarMoeda(_n(dados['taxas_entrega']))} de taxas de entrega.',
            if (cancelados > 0)
              '$cancelados ${cancelados == 1 ? 'pedido cancelado não entra' : 'pedidos cancelados não entram'} no total.',
          ].join('\n'),
          style: const TextStyle(color: Cores.textoSuave, height: 1.5),
        ),
      ],
    );
  }
}

class _PilulaVariacao extends StatelessWidget {
  final double variacao;
  final String comparado;
  const _PilulaVariacao({required this.variacao, required this.comparado});

  @override
  Widget build(BuildContext context) {
    final subiu = variacao >= 0;
    final cor = subiu ? Cores.sucesso : Cores.primaria;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: subiu ? Cores.sucessoClaro : Cores.primariaClara,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(subiu ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: cor),
          const SizedBox(width: 4),
          Text(
            '${variacao.abs().toStringAsFixed(0)}%',
            style: TextStyle(fontWeight: FontWeight.w800, color: cor),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text('vs. $comparado', style: TextStyle(color: cor)),
          ),
        ],
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  final String rotulo;
  final String valor;
  const _Numero({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(Esp.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: const TextStyle(fontSize: 15, color: Cores.textoSuave, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(valor, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ),
  );
}

class _Secao extends StatelessWidget {
  final String titulo;
  final Widget child;
  const _Secao({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(Esp.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Cores.textoSuave),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

/// Gráfico de barras simples: toque numa barra para ver o valor
class _Barras extends StatefulWidget {
  final List<double> valores;
  final List<String> rotulos;
  final List<String> dicas;
  const _Barras({required this.valores, required this.rotulos, required this.dicas});

  @override
  State<_Barras> createState() => _BarrasState();
}

class _BarrasState extends State<_Barras> {
  int? _selecionada;

  @override
  void didUpdateWidget(covariant _Barras antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.valores.length != widget.valores.length) _selecionada = null;
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.valores;
    if (v.isEmpty) return const Text('Sem vendas no período.', style: TextStyle(color: Cores.textoSuave));
    final maximo = v.reduce((a, b) => a > b ? a : b);
    // por padrão destaca o maior valor
    final destaque = _selecionada ?? (maximo > 0 ? v.indexOf(maximo) : null);
    final passo = v.length > 14 ? (v.length / 7).ceil() : 1;
    const alturaMax = 130.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // dica do valor da barra em destaque
        SizedBox(
          height: 34,
          child: destaque == null
              ? null
              : Align(
                  alignment: Alignment(v.length == 1 ? 0 : -1 + 2 * destaque / (v.length - 1), 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Cores.borda),
                      boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: Text(
                      widget.dicas[destaque],
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: alturaMax + 26,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < v.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selecionada = i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: v.length > 14 ? 1.5 : (v.length > 8 ? 3 : 6)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            height: maximo > 0 ? (v[i] / maximo * alturaMax).clamp(v[i] > 0 ? 4.0 : 2.0, alturaMax) : 2,
                            decoration: BoxDecoration(
                              color: v[i] == 0
                                  ? Cores.borda
                                  : (i == destaque ? Cores.primaria : const Color(0xFFF6A58C)),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 18,
                            child: (i % passo == 0 || i == v.length - 1)
                                ? FittedBox(
                                    child: Text(
                                      widget.rotulos[i],
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: i == destaque ? FontWeight.w800 : FontWeight.w500,
                                        color: i == destaque ? Cores.texto : Cores.textoSuave,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
