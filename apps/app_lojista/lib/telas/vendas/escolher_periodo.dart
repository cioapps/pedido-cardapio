import 'package:flutter/material.dart';

import '../../tema.dart';
import '../../widgets/comum.dart';
import 'periodo.dart';

/// Abre a janela de baixo "Escolher período". Retorna o período ou null se fechar.
Future<Periodo?> escolherPeriodo(BuildContext context, Periodo atual) => showModalBottomSheet<Periodo>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _EscolherPeriodo(atual: atual),
);

class _EscolherPeriodo extends StatefulWidget {
  final Periodo atual;
  const _EscolherPeriodo({required this.atual});

  @override
  State<_EscolherPeriodo> createState() => _EscolherPeriodoState();
}

class _EscolherPeriodoState extends State<_EscolherPeriodo> {
  late DateTime? _inicio = widget.atual.inicio;
  late DateTime? _fim = widget.atual.fim;
  late DateTime _mes = DateTime(widget.atual.fim.year, widget.atual.fim.month);

  void _tocarDia(DateTime dia) {
    setState(() {
      // 1º toque: início. 2º toque: fim (se for antes do início, vira o novo início)
      if (_inicio == null || _fim != null) {
        _inicio = dia;
        _fim = null;
      } else if (dia.isBefore(_inicio!)) {
        _fim = _inicio;
        _inicio = dia;
      } else {
        _fim = dia;
      }
    });
  }

  void _aplicar(Periodo p) {
    if (p.dias > 366) {
      mostrarMensagem(context, 'Escolha um período de até 1 ano.');
      return;
    }
    // se as datas batem com um atalho, usa o nome dele ("Mês passado")
    final atalho = Periodo.atalhos().where((a) => a.mesmoQue(p)).firstOrNull;
    Navigator.pop(context, atalho ?? p);
  }

  @override
  Widget build(BuildContext context) {
    final atalhos = Periodo.atalhos();
    final selecao = _inicio != null && _fim != null ? Periodo(_inicio!, _fim!) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Esp.m, 0, Esp.m, Esp.m),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Escolher período', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            // atalhos em 2 colunas
            LayoutBuilder(
              builder: (context, c) {
                final largura = (c.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final a in atalhos)
                      SizedBox(
                        width: largura,
                        child: _BotaoAtalho(
                          texto: a.atalho == '7 dias'
                              ? 'Últimos 7 dias'
                              : a.atalho == '30 dias'
                              ? 'Últimos 30 dias'
                              : a.atalho!,
                          selecionado: selecao != null && a.mesmoQue(selecao),
                          aoTocar: () => _aplicar(a),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ou escolha as datas', style: TextStyle(color: Cores.textoSuave)),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CampoData(rotulo: 'De', data: _inicio, ativo: _fim != null || _inicio == null),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CampoData(rotulo: 'Até', data: _fim, ativo: _inicio != null && _fim == null),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Calendario(
              mes: _mes,
              inicio: _inicio,
              fim: _fim,
              aoMudarMes: (m) => setState(() => _mes = m),
              aoTocarDia: _tocarDia,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: selecao == null ? null : () => _aplicar(selecao),
              child: Text(selecao == null ? 'Toque na data final' : 'Ver vendas'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotaoAtalho extends StatelessWidget {
  final String texto;
  final bool selecionado;
  final VoidCallback aoTocar;
  const _BotaoAtalho({required this.texto, required this.selecionado, required this.aoTocar});

  @override
  Widget build(BuildContext context) => Material(
    color: selecionado ? Cores.primariaClara : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: selecionado ? Cores.primaria : Cores.borda, width: selecionado ? 1.5 : 1),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: aoTocar,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(Icons.calendar_today_outlined, size: 20, color: selecionado ? Cores.primaria : Cores.textoSuave),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selecionado ? FontWeight.w800 : FontWeight.w600,
                  color: selecionado ? Cores.primaria : Cores.texto,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CampoData extends StatelessWidget {
  final String rotulo;
  final DateTime? data;
  final bool ativo;
  const _CampoData({required this.rotulo, required this.data, required this.ativo});

  @override
  Widget build(BuildContext context) => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ativo ? Cores.primaria : Cores.borda, width: ativo ? 1.5 : 1),
    ),
    child: Row(
      children: [
        Text(rotulo, style: const TextStyle(color: Cores.textoSuave)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            data == null ? '--/--/----' : dataCurta(data!),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

/// Calendário de um mês com seleção de intervalo. Dias futuros desabilitados.
class _Calendario extends StatelessWidget {
  final DateTime mes;
  final DateTime? inicio;
  final DateTime? fim;
  final ValueChanged<DateTime> aoMudarMes;
  final ValueChanged<DateTime> aoTocarDia;
  const _Calendario({
    required this.mes,
    required this.inicio,
    required this.fim,
    required this.aoMudarMes,
    required this.aoTocarDia,
  });

  @override
  Widget build(BuildContext context) {
    final hoje = Periodo.hoje;
    final diasNoMes = DateTime(mes.year, mes.month + 1, 0).day;
    final deslocamento = DateTime(mes.year, mes.month, 1).weekday % 7; // domingo = 0
    final podeAvancar = DateTime(mes.year, mes.month + 1).isBefore(DateTime(hoje.year, hoje.month + 1));
    final celulas = <DateTime?>[
      for (var i = 0; i < deslocamento; i++) null,
      for (var d = 1; d <= diasNoMes; d++) DateTime(mes.year, mes.month, d),
    ];

    bool dentro(DateTime d) => inicio != null && fim != null && !d.isBefore(inicio!) && !d.isAfter(fim!);

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Mês anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => aoMudarMes(DateTime(mes.year, mes.month - 1)),
            ),
            Expanded(
              child: Text(
                '${meses[mes.month - 1][0].toUpperCase()}${meses[mes.month - 1].substring(1)} ${mes.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              icon: const Icon(Icons.chevron_right),
              onPressed: podeAvancar ? () => aoMudarMes(DateTime(mes.year, mes.month + 1)) : null,
            ),
          ],
        ),
        Row(
          children: [
            for (final d in diasSemanaCurtos)
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Cores.textoSuave),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var linha = 0; linha < (celulas.length / 7).ceil(); linha++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final i = linha * 7 + col;
                      final dia = i < celulas.length ? celulas[i] : null;
                      if (dia == null) return const SizedBox(height: 44);
                      final futuro = dia.isAfter(hoje);
                      final ponta = dia == inicio || dia == fim;
                      final faixa = dentro(dia);
                      return GestureDetector(
                        onTap: futuro ? null : () => aoTocarDia(dia),
                        child: Container(
                          height: 44,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: faixa && !ponta ? Cores.primariaClara : null,
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(dia == inicio || col == 0 ? 22 : 0),
                              right: Radius.circular(dia == fim || col == 6 ? 22 : 0),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: ponta
                                ? const BoxDecoration(color: Cores.primaria, shape: BoxShape.circle)
                                : dia == hoje
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Cores.primariaBorda),
                                  )
                                : null,
                            child: Text(
                              '${dia.day}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: ponta ? FontWeight.w800 : FontWeight.w500,
                                color: ponta
                                    ? Colors.white
                                    : futuro
                                    ? const Color(0xFFC4C4CC)
                                    : Cores.texto,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
