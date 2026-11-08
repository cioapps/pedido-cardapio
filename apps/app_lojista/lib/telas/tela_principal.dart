import 'package:flutter/material.dart';

import '../servicos/pedidos_servico.dart';
import '../servicos/whatsapp_servico.dart';
import 'cardapio/tela_cardapio.dart';
import 'loja/tela_loja.dart';
import 'tela_configuracoes.dart';
import 'tela_pedidos.dart';
import 'tela_vendas.dart';

/// Barra inferior: Pedidos | Vendas | Cardápio | Loja | Ajustes.
/// IndexedStack mantém os pedidos (e o alarme) vivos nas outras abas.
class TelaPrincipal extends StatefulWidget {
  const TelaPrincipal({super.key});

  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal> {
  int _aba = 0;
  final _visitadas = <int>{0};

  @override
  Widget build(BuildContext context) {
    final pedidos = PedidosServico.instancia;
    final whatsapp = WhatsappServico.instancia;
    return Scaffold(
      // Teste grátis não mostra contagem: quando vence, a TelaInicio troca para a tela de bloqueio
      body: IndexedStack(index: _aba, children: [
        const TelaPedidos(),
        // só monta as outras abas quando abertas pela primeira vez
        _visitadas.contains(1) ? const TelaVendas() : const SizedBox(),
        _visitadas.contains(2) ? const TelaCardapio() : const SizedBox(),
        _visitadas.contains(3) ? const TelaLoja() : const SizedBox(),
        _visitadas.contains(4) ? const TelaConfiguracoes() : const SizedBox(),
      ]),
      bottomNavigationBar: ListenableBuilder(
        listenable: Listenable.merge([pedidos, whatsapp]),
        builder: (context, _) {
          final novos = pedidos.pedidos.where((p) => p.statusPedido == 'novo').length + whatsapp.quantidadeProntos;
          return NavigationBar(
            selectedIndex: _aba,
            onDestinationSelected: (i) {
              // Vendas: atualiza os números sempre que a aba é aberta de novo
              if (i == 1 && _visitadas.contains(1)) TelaVendas.atualizar.value++;
              setState(() {
                _aba = i;
                _visitadas.add(i);
              });
            },
            destinations: [
              NavigationDestination(
                icon: Badge(isLabelVisible: novos > 0, label: Text('$novos'), child: const Icon(Icons.receipt_long_outlined)),
                selectedIcon:
                    Badge(isLabelVisible: novos > 0, label: Text('$novos'), child: const Icon(Icons.receipt_long)),
                label: 'Pedidos',
              ),
              const NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Vendas'),
              const NavigationDestination(
                  icon: Icon(Icons.restaurant_menu_outlined), selectedIcon: Icon(Icons.restaurant_menu), label: 'Cardápio'),
              const NavigationDestination(
                  icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Loja'),
              const NavigationDestination(
                  icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
            ],
          );
        },
      ),
    );
  }
}
