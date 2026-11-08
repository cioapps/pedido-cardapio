import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../servicos/gestao_servico.dart';
import '../../servicos/impressora_servico.dart';
import '../../servicos/pedidos_servico.dart';
import '../../tema.dart';
import '../../widgets/comum.dart';
import '../cardapio/tela_cardapio.dart';
import '../tela_configuracoes.dart';
import 'tela_bairros.dart';
import 'tela_dados_loja.dart';
import 'tela_horarios.dart';
import 'tela_whatsapp.dart';

/// Aba Loja: primeiros passos (loja nova), link do cardápio e cadastros
class TelaLoja extends StatefulWidget {
  const TelaLoja({super.key});

  @override
  State<TelaLoja> createState() => _TelaLojaState();
}

class _TelaLojaState extends State<TelaLoja> {
  final _servico = PedidosServico.instancia;
  final _gestao = GestaoServico.instancia;

  @override
  void initState() {
    super.initState();
    _atualizarContagens();
  }

  /// Carrega o necessário para saber quais passos já foram feitos
  Future<void> _atualizarContagens() async {
    try {
      await Future.wait([
        if (!_gestao.cardapioCarregado) _gestao.carregarCardapio(),
        _gestao.carregarBairros(),
      ]);
    } catch (_) {
      // sem internet: os passos aparecem como pendentes
    }
    if (mounted) setState(() {});
  }

  Future<void> _abrir(Widget tela) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    _atualizarContagens();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_servico, _gestao]),
      builder: (context, _) {
        final e = _servico.empresa;
        if (e == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final link = '${Config.urlCardapio}/${e.slugEmpresa}';

        final passos = [
          _Passo('Complete os dados da loja', 'WhatsApp, endereço e logo',
              (e.telefoneWhatsapp ?? '').isNotEmpty, () => _abrir(const TelaDadosLoja())),
          _Passo('Cadastre seus produtos', 'Lanches, bebidas, porções...', _gestao.produtos.isNotEmpty,
              () => _abrir(const TelaCardapio())),
          _Passo('Cadastre os bairros de entrega', 'E a taxa de cada um', _gestao.bairros.isNotEmpty,
              () => _abrir(const TelaBairros())),
          _Passo('Conecte a impressora', 'Opcional: imprime o pedido na cozinha', ImpressoraServico.instancia.configurada,
              () => _abrir(const TelaConfiguracoes())),
        ];
        final feitos = passos.where((p) => p.feito).length;
        // a impressora (último passo) é opcional: o guia some quando os obrigatórios estão feitos
        final obrigatoriosFeitos = passos.take(3).every((p) => p.feito);
        final mostrarPassos = _gestao.cardapioCarregado && !obrigatoriosFeitos;

        return Scaffold(
          appBar: AppBar(title: const Text('Minha loja')),
          body: RefreshIndicator(
            onRefresh: _atualizarContagens,
            child: ListView(padding: const EdgeInsets.fromLTRB(Esp.m, 4, Esp.m, 40), children: [
              if (mostrarPassos) ...[
                _CartaoPrimeirosPassos(passos: passos, feitos: feitos),
                const SizedBox(height: Esp.m),
              ],
              if (e.moduloCardapio)
                _CartaoLink(link: link)
              else
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.chat),
                    title: Text('Pedidos pelo WhatsApp'),
                    subtitle: Text('O cardápio online não está ativo nesta loja.'),
                  ),
                ),
              const SecaoTitulo('Configurações da loja'),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  _ItemMenu(
                    icone: Icons.store,
                    titulo: 'Dados da loja',
                    subtitulo: 'Nome, WhatsApp, endereço, logo e cor',
                    aoTocar: () => _abrir(const TelaDadosLoja()),
                  ),
                  const Divider(indent: 72),
                  _ItemMenu(
                    icone: Icons.schedule,
                    titulo: 'Horário de funcionamento',
                    subtitulo: e.usarHorarios ? 'Abre e fecha sozinha' : 'Você abre e fecha na tela de pedidos',
                    aoTocar: () => _abrir(const TelaHorarios()),
                  ),
                  const Divider(indent: 72),
                  _ItemMenu(
                    icone: Icons.delivery_dining,
                    titulo: 'Bairros e taxas de entrega',
                    subtitulo: _gestao.bairros.isEmpty
                        ? 'Nenhum bairro cadastrado'
                        : '${_gestao.bairros.where((b) => b.ativo).length} bairros atendidos',
                    aoTocar: () => _abrir(const TelaBairros()),
                  ),
                  if (e.moduloWhatsapp) ...[
                    const Divider(indent: 72),
                    _ItemMenu(
                      icone: Icons.chat,
                      titulo: 'WhatsApp com IA',
                      subtitulo: 'A IA monta os pedidos das conversas',
                      aoTocar: () => _abrir(const TelaWhatsapp()),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _Passo {
  final String titulo;
  final String subtitulo;
  final bool feito;
  final VoidCallback aoTocar;
  _Passo(this.titulo, this.subtitulo, this.feito, this.aoTocar);
}

class _CartaoPrimeirosPassos extends StatelessWidget {
  final List<_Passo> passos;
  final int feitos;
  const _CartaoPrimeirosPassos({required this.passos, required this.feitos});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Cores.primaria, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Primeiros passos', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('$feitos de ${passos.length} feitos. Siga a ordem e sua loja fica pronta para vender.',
                style: const TextStyle(color: Cores.textoSuave)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: feitos / passos.length,
                minHeight: 8,
                backgroundColor: Cores.fundo,
                color: Cores.sucesso,
              ),
            ),
          ]),
        ),
        for (var i = 0; i < passos.length; i++)
          ListTile(
            onTap: passos[i].aoTocar,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: passos[i].feito ? Cores.sucesso : Cores.primariaClara,
              child: passos[i].feito
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: Cores.primaria)),
            ),
            title: Text(
              passos[i].titulo,
              style: TextStyle(
                decoration: passos[i].feito ? TextDecoration.lineThrough : null,
                color: passos[i].feito ? Cores.textoSuave : Cores.texto,
              ),
            ),
            subtitle: Text(passos[i].subtitulo),
            trailing: passos[i].feito ? null : const Icon(Icons.chevron_right),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _CartaoLink extends StatelessWidget {
  final String link;
  const _CartaoLink({required this.link});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Cores.primaria,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(Esp.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.link, color: Colors.white),
            SizedBox(width: 8),
            Text('Link do seu cardápio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
          const SizedBox(height: 4),
          const Text('Mande para os clientes no WhatsApp, Instagram e status.',
              style: TextStyle(color: Color(0xFFFDE8E8))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: SelectableText(link.replaceFirst(RegExp(r'^https?://'), ''),
                style: const TextStyle(fontWeight: FontWeight.w600, color: Cores.texto)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Cores.primaria),
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: 'Confira nosso cardápio e faça seu pedido: $link',
                )),
                icon: const Icon(Icons.share),
                label: const Text('Compartilhar'),
              ),
            ),
            const SizedBox(width: 8),
            _BotaoClaro(
              icone: Icons.copy,
              rotulo: 'Copiar',
              aoTocar: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) mostrarMensagem(context, 'Link copiado!');
              },
            ),
            const SizedBox(width: 8),
            _BotaoClaro(
              icone: Icons.visibility,
              rotulo: 'Ver',
              aoTocar: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _BotaoClaro extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final VoidCallback aoTocar;
  const _BotaoClaro({required this.icone, required this.rotulo, required this.aoTocar});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white70, width: 1.5),
        ),
        onPressed: aoTocar,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 20),
          Text(rotulo, style: const TextStyle(fontSize: 12)),
        ]),
      );
}

class _ItemMenu extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final VoidCallback aoTocar;
  const _ItemMenu({required this.icone, required this.titulo, required this.subtitulo, required this.aoTocar});

  @override
  Widget build(BuildContext context) => ListTile(
        minVerticalPadding: 12,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Cores.primariaClara, borderRadius: BorderRadius.circular(10)),
          child: Icon(icone, color: Cores.primaria),
        ),
        title: Text(titulo),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right),
        onTap: aoTocar,
      );
}
