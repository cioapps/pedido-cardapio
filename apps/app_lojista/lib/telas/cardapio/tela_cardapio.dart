import 'package:flutter/material.dart';

import '../../servicos/gestao_servico.dart';
import '../../widgets/comum.dart';
import 'aba_opcoes.dart';
import 'aba_produtos.dart';

/// Aba Cardápio: Produtos (categorias + produtos) e Opções (grupos + opções)
class TelaCardapio extends StatefulWidget {
  const TelaCardapio({super.key});

  @override
  State<TelaCardapio> createState() => _TelaCardapioState();
}

class _TelaCardapioState extends State<TelaCardapio> {
  final _gestao = GestaoServico.instancia;
  bool _ordenando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      await _gestao.carregarCardapio();
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar o cardápio. Verifique a internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cardápio'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ordenando
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(48, 44)),
                      onPressed: () => setState(() => _ordenando = false),
                      icon: const Icon(Icons.check),
                      label: const Text('Pronto'),
                    )
                  : TextButton.icon(
                      onPressed: () => setState(() => _ordenando = true),
                      icon: const Icon(Icons.swap_vert),
                      label: const Text('Ordenar'),
                    ),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Produtos'), Tab(text: 'Adicionais e opções')]),
        ),
        body: ListenableBuilder(
          listenable: _gestao,
          builder: (context, _) {
            if (_erro != null) {
              return EstadoVazio(
                icone: Icons.wifi_off,
                texto: _erro!,
                acao: FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
              );
            }
            if (!_gestao.cardapioCarregado) return const Center(child: CircularProgressIndicator());
            return TabBarView(children: [
              AbaProdutos(ordenando: _ordenando, aoAtualizar: _carregar),
              AbaOpcoes(ordenando: _ordenando, aoAtualizar: _carregar),
            ]);
          },
        ),
      ),
    );
  }
}
