import 'package:flutter/material.dart';

import '../servicos/gestao_servico.dart';
import '../servicos/notificacoes_servico.dart';
import '../servicos/pedidos_servico.dart';
import '../servicos/sessao.dart';
import '../servicos/whatsapp_servico.dart';
import 'tela_bloqueio.dart';
import 'tela_nova_loja.dart';
import 'tela_principal.dart';

/// Depois do login: carrega a loja da conta. Sem loja, abre o cadastro dela.
class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key});

  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  final _servico = PedidosServico.instancia;
  bool? _temLoja;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _temLoja = null);
    final tem = await _servico.iniciar();
    final empresa = _servico.empresa;
    if (empresa != null && empresa.moduloWhatsapp) {
      WhatsappServico.instancia.iniciar(empresa.id, empresa.slugEmpresa);
    }
    // aviso de pedido com o app fechado
    if (empresa != null) NotificacoesServico.instancia.registrar();
    if (mounted) setState(() => _temLoja = tem);
  }

  @override
  void dispose() {
    _servico.encerrar();
    WhatsappServico.instancia.encerrar();
    GestaoServico.instancia.limpar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (_temLoja) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      false => TelaNovaLoja(aoCriar: _carregar, aoSair: sairDaConta),
      true => ListenableBuilder(
          listenable: _servico,
          builder: (_, _) => _servico.assinaturaLiberada ? const TelaPrincipal() : const TelaBloqueio(),
        ),
    };
  }
}
