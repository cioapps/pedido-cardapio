import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../servicos/impressora_servico.dart';
import '../servicos/pedidos_servico.dart';
import '../servicos/sessao.dart';
import '../widgets/comum.dart';

class TelaConfiguracoes extends StatefulWidget {
  const TelaConfiguracoes({super.key});

  @override
  State<TelaConfiguracoes> createState() => _TelaConfiguracoesState();
}

class _TelaConfiguracoesState extends State<TelaConfiguracoes> {
  final _imp = ImpressoraServico.instancia;
  late final _ip = TextEditingController(text: _imp.config.ipRede);
  late final _porta = TextEditingController(text: '${_imp.config.portaRede}');
  List<BluetoothInfo> _pareadas = [];
  bool _buscando = false;
  bool _testando = false;

  ConfigImpressora get c => _imp.config;

  Future<void> _salvar() async {
    await c.salvar();
    setState(() {});
  }

  Future<void> _buscarBluetooth() async {
    setState(() => _buscando = true);
    try {
      _pareadas = await _imp.listarPareadas();
      if (_pareadas.isEmpty) _mostrar('Nenhuma impressora pareada. Pareie nas configurações de Bluetooth do Android.');
    } catch (e) {
      _mostrar('$e'.replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _buscando = false);
  }

  Future<void> _testar() async {
    setState(() => _testando = true);
    try {
      await _imp.imprimirTeste(PedidosServico.instancia.empresa?.nomeEmpresa ?? 'Teste');
      _mostrar('Teste enviado!');
    } catch (e) {
      _mostrar('$e'.replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _testando = false);
  }

  void _mostrar(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final empresa = PedidosServico.instancia.empresa;
    final titulo = Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Impressora', style: titulo),
          const SizedBox(height: 8),
          SegmentedButton<TipoImpressora>(
            segments: const [
              ButtonSegment(value: TipoImpressora.nenhuma, label: Text('Nenhuma')),
              ButtonSegment(value: TipoImpressora.bluetooth, label: Text('Bluetooth'), icon: Icon(Icons.bluetooth)),
              ButtonSegment(value: TipoImpressora.rede, label: Text('Rede / Wi-Fi'), icon: Icon(Icons.wifi)),
            ],
            selected: {c.tipo},
            onSelectionChanged: (s) {
              c.tipo = s.first;
              _salvar();
              if (c.tipo == TipoImpressora.bluetooth && _pareadas.isEmpty) _buscarBluetooth();
            },
          ),
          const SizedBox(height: 12),
          if (c.tipo == TipoImpressora.bluetooth) ...[
            if (c.nomeBluetooth.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.print),
                title: Text(c.nomeBluetooth),
                subtitle: Text(c.enderecoBluetooth),
              ),
            OutlinedButton.icon(
              onPressed: _buscando ? null : _buscarBluetooth,
              icon: const Icon(Icons.search),
              label: Text(_buscando ? 'Buscando...' : 'Escolher impressora pareada'),
            ),
            RadioGroup<String>(
              groupValue: c.enderecoBluetooth,
              onChanged: (mac) {
                final d = _pareadas.firstWhere((x) => x.macAdress == mac);
                c.enderecoBluetooth = d.macAdress;
                c.nomeBluetooth = d.name;
                _salvar();
              },
              child: Column(children: [
                for (final d in _pareadas)
                  RadioListTile<String>(
                    value: d.macAdress,
                    title: Text(d.name.isEmpty ? 'Sem nome' : d.name),
                    subtitle: Text(d.macAdress),
                  ),
              ]),
            ),
          ],
          if (c.tipo == TipoImpressora.rede)
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ip,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'IP da impressora', hintText: '192.168.0.100', border: OutlineInputBorder()),
                  onChanged: (v) {
                    c.ipRede = v.trim();
                    c.salvar();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _porta,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Porta', border: OutlineInputBorder()),
                  onChanged: (v) {
                    c.portaRede = int.tryParse(v) ?? 9100;
                    c.salvar();
                  },
                ),
              ),
            ]),
          if (c.tipo != TipoImpressora.nenhuma) ...[
            const SizedBox(height: 16),
            const Text('Largura do papel'),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('58 mm')),
                ButtonSegment(value: false, label: Text('80 mm')),
              ],
              selected: {c.papel58mm},
              onSelectionChanged: (s) {
                c.papel58mm = s.first;
                _salvar();
              },
            ),
            const SizedBox(height: 16),
            const Text('Imprimir automaticamente'),
            const SizedBox(height: 6),
            SegmentedButton<ImpressaoAutomatica>(
              segments: const [
                ButtonSegment(value: ImpressaoAutomatica.desligada, label: Text('Não')),
                ButtonSegment(value: ImpressaoAutomatica.aoChegar, label: Text('Ao chegar')),
                ButtonSegment(value: ImpressaoAutomatica.aoAceitar, label: Text('Ao aceitar')),
              ],
              selected: {c.automatica},
              onSelectionChanged: (s) {
                c.automatica = s.first;
                _salvar();
              },
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('Número de vias')),
              IconButton(
                onPressed: c.vias > 1 ? () { c.vias--; _salvar(); } : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('${c.vias}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: c.vias < 5 ? () { c.vias++; _salvar(); } : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _testando || !_imp.configurada
                  ? null
                  : () async {
                      await c.salvar();
                      await _testar();
                    },
              icon: const Icon(Icons.print),
              label: Text(_testando ? 'Imprimindo...' : 'Imprimir teste'),
            ),
          ],
          const Divider(height: 40),
          Text('Conta', style: titulo),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle),
            title: Text(Supabase.instance.client.auth.currentUser?.email ?? ''),
            subtitle: Text(empresa?.nomeEmpresa ?? ''),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await confirmar(context,
                  titulo: 'Sair da conta?',
                  texto: 'Com a conta fora, o app para de receber e imprimir pedidos.',
                  botao: 'Sair');
              if (ok) await sairDaConta();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sair da conta'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    c.salvar();
    _ip.dispose();
    _porta.dispose();
    super.dispose();
  }
}
