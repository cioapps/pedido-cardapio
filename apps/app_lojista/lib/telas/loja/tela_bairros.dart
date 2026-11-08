import 'package:flutter/material.dart';

import '../../modelos/gestao.dart';
import '../../servicos/gestao_servico.dart';
import '../../util/formatar.dart';
import '../../widgets/comum.dart';

/// Bairros atendidos e a taxa de entrega de cada um
class TelaBairros extends StatefulWidget {
  const TelaBairros({super.key});

  @override
  State<TelaBairros> createState() => _TelaBairrosState();
}

class _TelaBairrosState extends State<TelaBairros> {
  final _gestao = GestaoServico.instancia;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      await _gestao.carregarBairros();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _executar(Future<void> Function() acao) async {
    try {
      await acao();
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
  }

  Future<void> _adicionar() async {
    final nomes = TextEditingController();
    final taxa = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Adicionar bairros'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nomes,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Bairro(s)',
              helperText: 'Vários de uma vez: separe por vírgula',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          CampoMoeda(controle: taxa, rotulo: 'Taxa de entrega'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Adicionar')),
        ],
      ),
    );
    if (ok != true) return;
    await _executar(() async {
      final qtd = await _gestao.adicionarBairros(nomes.text, lerNumero(taxa.text.isEmpty ? '0' : taxa.text));
      if (mounted && qtd > 1) mostrarMensagem(context, '$qtd bairros adicionados.');
    });
  }

  Future<void> _editarTaxa(Bairro b) async {
    final taxa = TextEditingController(text: numeroParaCampo(b.taxaEntrega));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(b.nomeBairro),
        content: CampoMoeda(controle: taxa, rotulo: 'Taxa de entrega'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, null),
            child: const Text('Cancelar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok == true) await _executar(() => _gestao.atualizarBairro(b, taxa: lerNumero(taxa.text)));
  }

  Future<void> _remover(Bairro b) async {
    final ok = await confirmar(context, titulo: 'Remover "${b.nomeBairro}"?', botao: 'Remover', perigo: true);
    if (ok) await _executar(() => _gestao.excluirBairro(b));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bairros e taxas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adicionar,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar bairro'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: _gestao,
              builder: (context, _) {
                final bairros = _gestao.bairros;
                if (bairros.isEmpty) {
                  return const EstadoVazio(
                    icone: Icons.delivery_dining,
                    texto: 'Cadastre os bairros que você atende.\nO cliente escolhe o bairro no pedido e a taxa é somada.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: bairros.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final b = bairros[i];
                    return ListTile(
                      title: Text(b.nomeBairro, style: TextStyle(color: b.ativo ? null : Colors.grey)),
                      subtitle: Text(b.ativo
                          ? (b.taxaEntrega > 0 ? 'Taxa ${formatarMoeda(b.taxaEntrega)}' : 'Entrega grátis')
                          : 'Não atende no momento'),
                      onTap: () => _editarTaxa(b),
                      onLongPress: () => _remover(b),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          value: b.ativo,
                          onChanged: (v) => _executar(() => _gestao.atualizarBairro(b, ativo: v)),
                        ),
                        IconButton(
                          tooltip: 'Remover',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remover(b),
                        ),
                      ]),
                    );
                  },
                );
              },
            ),
    );
  }
}
