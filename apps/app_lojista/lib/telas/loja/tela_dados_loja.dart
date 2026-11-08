import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../servicos/imagem_servico.dart';
import '../../servicos/pedidos_servico.dart';
import '../../util/formatar.dart';
import '../../widgets/comum.dart';

const _cores = ['#E63946', '#F77F00', '#2A9D8F', '#1D3557', '#6A4C93', '#111827', '#B5179E', '#2B9348'];

Color corDeHex(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.tryParse('FF$h', radix: 16) ?? 0xFFE63946);
}

/// Nome, WhatsApp, endereço, cor, logo, pedido mínimo e tempo de entrega
class TelaDadosLoja extends StatefulWidget {
  const TelaDadosLoja({super.key});

  @override
  State<TelaDadosLoja> createState() => _TelaDadosLojaState();
}

class _TelaDadosLojaState extends State<TelaDadosLoja> {
  final _servico = PedidosServico.instancia;
  late final _e = _servico.empresa!;
  late final _nome = TextEditingController(text: _e.nomeEmpresa);
  late final _telefone = TextEditingController(text: telefoneParaCampo(_e.telefoneWhatsapp));
  late final _endereco = TextEditingController(text: _e.enderecoEmpresa);
  late final _minimo = TextEditingController(text: _e.pedidoMinimo > 0 ? numeroParaCampo(_e.pedidoMinimo) : '');
  late final _tempo = TextEditingController(text: '${_e.tempoEntregaMinutos}');
  late String _cor = _e.corPrincipal.toUpperCase();
  late String? _logo = _e.logoUrl;
  bool _enviandoLogo = false;
  bool _salvando = false;

  Future<void> _trocarLogo() async {
    setState(() => _enviandoLogo = true);
    try {
      final url = await ImagemServico.instancia
          .escolherEEnviar(idEmpresa: _e.id, tipo: TipoImagem.logo, origem: ImageSource.gallery);
      if (url != null) setState(() => _logo = url);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
    if (mounted) setState(() => _enviandoLogo = false);
  }

  Future<void> _salvar() async {
    if (_nome.text.trim().isEmpty) return mostrarMensagem(context, 'Informe o nome da loja.');
    final telefone = apenasDigitos(_telefone.text);
    setState(() => _salvando = true);
    try {
      await _servico.atualizarEmpresa({
        'nome_empresa': _nome.text.trim(),
        'telefone_whatsapp': telefone.isEmpty ? null : telefone,
        'endereco_empresa': _endereco.text.trim().isEmpty ? null : _endereco.text.trim(),
        'cor_principal': _cor,
        'logo_url': _logo,
        'pedido_minimo': lerNumero(_minimo.text),
        'tempo_entrega_minutos': (int.tryParse(_tempo.text) ?? 45).clamp(1, 600),
      });
      if (mounted) {
        mostrarMensagem(context, 'Alterações salvas!');
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
      appBar: AppBar(title: const Text('Dados da loja')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          InkWell(
            onTap: _enviandoLogo ? null : _trocarLogo,
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: cores.surfaceContainer,
              backgroundImage: _logo == null ? null : NetworkImage(_logo!),
              child: _enviandoLogo
                  ? const CircularProgressIndicator()
                  : _logo == null
                      ? Icon(Icons.add_a_photo, color: cores.primary)
                      : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Logo', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(children: [
                TextButton(onPressed: _enviandoLogo ? null : _trocarLogo, child: Text(_logo == null ? 'Adicionar' : 'Trocar')),
                if (_logo != null) TextButton(onPressed: () => setState(() => _logo = null), child: const Text('Remover')),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _nome,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nome da loja', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _telefone,
          keyboardType: TextInputType.phone,
          inputFormatters: [MascaraTelefone()],
          decoration: const InputDecoration(
            labelText: 'WhatsApp da loja',
            helperText: 'O cliente fala com você por este número',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endereco,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Endereço (opcional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: CampoMoeda(controle: _minimo, rotulo: 'Pedido mínimo')),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _tempo,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Tempo de entrega',
                suffixText: 'min',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        const Text('Cor do cardápio', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in _cores)
            InkWell(
              onTap: () => setState(() => _cor = c),
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: corDeHex(c),
                child: _cor == c ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            ),
        ]),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _salvando || _enviandoLogo ? null : _salvar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(_salvando ? 'Salvando...' : 'Salvar'),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    for (final c in [_nome, _telefone, _endereco, _minimo, _tempo]) {
      c.dispose();
    }
    super.dispose();
  }
}
