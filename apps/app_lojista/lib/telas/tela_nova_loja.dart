import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../util/formatar.dart';
import '../widgets/comum.dart';

/// Primeiro acesso: cria a loja da conta (RPC criar_empresa)
class TelaNovaLoja extends StatefulWidget {
  final Future<void> Function() aoCriar;
  final Future<void> Function() aoSair;
  const TelaNovaLoja({super.key, required this.aoCriar, required this.aoSair});

  @override
  State<TelaNovaLoja> createState() => _TelaNovaLojaState();
}

class _TelaNovaLojaState extends State<TelaNovaLoja> {
  final _nome = TextEditingController();
  final _slug = TextEditingController();
  final _telefone = TextEditingController();
  bool _slugEditado = false;
  bool _enviando = false;
  String? _erro;

  static final _padraoSlug = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  Future<void> _criar() async {
    final nome = _nome.text.trim();
    final slug = _slug.text.trim();
    final telefone = apenasDigitos(_telefone.text);
    String? erro;
    if (nome.isEmpty) {
      erro = 'Informe o nome da loja.';
    } else if (!_padraoSlug.hasMatch(slug)) {
      erro = 'O link só pode ter letras minúsculas, números e hífen.';
    } else if (telefone.length < 10) {
      erro = 'Informe o WhatsApp da loja com DDD.';
    }
    if (erro != null) return setState(() => _erro = erro);

    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await Supabase.instance.client.rpc('criar_empresa', params: {
        'p_nome_empresa': nome,
        'p_slug_empresa': slug,
        'p_telefone_whatsapp': telefone,
      });
      await widget.aoCriar();
    } catch (e) {
      if (mounted) setState(() => _erro = mensagemErro(e));
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar sua loja'),
        actions: [TextButton(onPressed: widget.aoSair, child: const Text('Sair'))],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Só mais um passo. Depois você cadastra o cardápio aqui mesmo no app.'),
          const SizedBox(height: 20),
          TextField(
            controller: _nome,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome da loja', border: OutlineInputBorder()),
            onChanged: (v) {
              if (!_slugEditado) _slug.text = gerarSlug(v);
              setState(() {});
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _slug,
            decoration: InputDecoration(
              labelText: 'Link do cardápio',
              helperText: '${Config.urlCardapio.replaceFirst(RegExp(r'^https?://'), '')}/${_slug.text}',
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              _slugEditado = true;
              final limpo = v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');
              if (limpo != v) {
                _slug.value = TextEditingValue(text: limpo, selection: TextSelection.collapsed(offset: limpo.length));
              }
              setState(() {});
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _telefone,
            keyboardType: TextInputType.phone,
            inputFormatters: [MascaraTelefone()],
            decoration: const InputDecoration(
              labelText: 'WhatsApp da loja',
              hintText: '(11) 99999-9999',
              border: OutlineInputBorder(),
            ),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 14),
            Text(_erro!, style: TextStyle(color: cores.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _enviando ? null : _criar,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_enviando ? 'Criando...' : 'Criar loja'),
          ),
        ]),
      ),
    );
  }
}
