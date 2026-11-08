import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../servicos/pedidos_servico.dart';
import '../servicos/sessao.dart';

/// Assinatura vencida ou bloqueada pelo administrador
class TelaBloqueio extends StatefulWidget {
  const TelaBloqueio({super.key});

  @override
  State<TelaBloqueio> createState() => _TelaBloqueioState();
}

class _TelaBloqueioState extends State<TelaBloqueio> {
  final _servico = PedidosServico.instancia;
  bool _verificando = false;

  Future<void> _verificar() async {
    setState(() => _verificando = true);
    await _servico.verificarAssinatura();
    if (mounted) setState(() => _verificando = false);
    if (mounted && !_servico.assinaturaLiberada) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ainda bloqueada. Fale com o suporte para liberar.')));
    }
  }

  void _falarComSuporte() {
    final loja = _servico.empresa?.nomeEmpresa ?? '';
    final texto = Uri.encodeComponent('Olá! Quero ativar a assinatura da loja $loja.');
    var numero = Config.whatsappSuporte.replaceAll(RegExp(r'\D'), '');
    if (numero.length <= 11) numero = '55$numero';
    launchUrl(Uri.parse('https://wa.me/$numero?text=$texto'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final teste = _servico.emTeste;
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(teste ? Icons.hourglass_bottom : Icons.lock_outline, size: 64, color: cores.primary),
              const SizedBox(height: 16),
              Text(
                teste ? 'Seu período de teste acabou' : 'Assinatura bloqueada',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enquanto isso, o cardápio online não recebe pedidos e o app não toca nem imprime. '
                'Seus produtos e dados continuam salvos.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (Config.whatsappSuporte.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: _falarComSuporte,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.chat),
                  label: const Text('Ativar pelo WhatsApp'),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton(
                onPressed: _verificando ? null : _verificar,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(_verificando ? 'Verificando...' : 'Já ativei, verificar de novo'),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: sairDaConta, child: const Text('Sair da conta')),
            ]),
          ),
        ),
      ),
    );
  }
}
