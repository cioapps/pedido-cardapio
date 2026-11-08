import 'package:flutter/material.dart';

import '../../modelos/gestao.dart';
import '../../servicos/gestao_servico.dart';
import '../../servicos/pedidos_servico.dart';
import '../../widgets/comum.dart';

/// Horário de funcionamento: várias faixas por dia (ex.: 11:00–14:00 e 18:00–23:00)
class TelaHorarios extends StatefulWidget {
  const TelaHorarios({super.key});

  @override
  State<TelaHorarios> createState() => _TelaHorariosState();
}

class _TelaHorariosState extends State<TelaHorarios> {
  final _gestao = GestaoServico.instancia;
  final _pedidos = PedidosServico.instancia;
  late bool _usar = _pedidos.empresa!.usarHorarios;
  List<Horario>? _horarios;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _gestao.carregarHorarios().then((h) {
      if (mounted) setState(() => _horarios = h);
    }).catchError((Object e) {
      if (mounted) {
        mostrarErro(context, e);
        setState(() => _horarios = []);
      }
    });
  }

  List<Horario> _doDia(int dia) => _horarios!.where((h) => h.diaSemana == dia).toList();

  Future<void> _escolherHora(Horario h, bool abertura) async {
    final atual = (abertura ? h.horaAbertura : h.horaFechamento).split(':');
    final escolhida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(atual[0]), minute: int.parse(atual[1])),
      builder: (c, filho) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: filho!),
    );
    if (escolhida == null) return;
    final texto = '${escolhida.hour.toString().padLeft(2, '0')}:${escolhida.minute.toString().padLeft(2, '0')}';
    setState(() => abertura ? h.horaAbertura = texto : h.horaFechamento = texto);
  }

  void _copiarParaTodos(int dia) {
    final modelo = _doDia(dia);
    setState(() {
      _horarios!.removeWhere((h) => h.diaSemana != dia);
      for (var d = 0; d < 7; d++) {
        if (d == dia) continue;
        for (final h in modelo) {
          _horarios!.add(Horario(d, h.horaAbertura, h.horaFechamento));
        }
      }
    });
    mostrarMensagem(context, 'Horários de ${diasSemana[dia]} copiados para todos os dias.');
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await _gestao.salvarHorarios(_horarios!);
      await _pedidos.atualizarEmpresa({'usar_horarios': _usar});
      if (mounted) {
        mostrarMensagem(context, 'Horários salvos!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
    if (mounted) setState(() => _salvando = false);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Horário de funcionamento')),
      body: _horarios == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Abrir e fechar sozinha'),
                subtitle: Text(_usar
                    ? 'A loja só aceita pedidos nos horários abaixo (e quando estiver "Aberta").'
                    : 'Desligado: você abre e fecha pelo botão na tela de pedidos.'),
                value: _usar,
                onChanged: (v) => setState(() => _usar = v),
              ),
              if (_usar)
                for (var dia = 0; dia < 7; dia++) _cartaoDia(dia, cores),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _salvando ? null : _salvar,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(_salvando ? 'Salvando...' : 'Salvar horários'),
              ),
            ]),
    );
  }

  Widget _cartaoDia(int dia, ColorScheme cores) {
    final faixas = _doDia(dia);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cores.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(diasSemana[dia], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            if (faixas.isNotEmpty)
              TextButton(onPressed: () => _copiarParaTodos(dia), child: const Text('Copiar p/ todos')),
          ]),
          if (faixas.isEmpty) Text('Fechado', style: TextStyle(color: cores.outline)),
          for (final h in faixas)
            Row(children: [
              OutlinedButton(onPressed: () => _escolherHora(h, true), child: Text(h.horaAbertura)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('às')),
              OutlinedButton(onPressed: () => _escolherHora(h, false), child: Text(h.horaFechamento)),
              const Spacer(),
              IconButton(
                tooltip: 'Remover horário',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _horarios!.remove(h)),
              ),
            ]),
          TextButton.icon(
            onPressed: () => setState(() => _horarios!.add(Horario(dia, '18:00', '23:00'))),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar horário'),
          ),
        ]),
      ),
    );
  }
}
