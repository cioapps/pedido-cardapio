import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema.dart';
import '../util/formatar.dart';

/// Diálogo de confirmação. Retorna true se o lojista confirmou.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  String? texto,
  String botao = 'Confirmar',
  bool perigo = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: texto == null ? null : Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: perigo ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(botao),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Pede um texto (ex.: nome da categoria). Retorna null se cancelar.
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  String inicial = '',
  String rotulo = 'Nome',
  String botao = 'Salvar',
}) {
  final controle = TextEditingController(text: inicial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: controle,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, controle.text.trim()), child: Text(botao)),
      ],
    ),
  ).then((v) => v == null || v.isEmpty ? null : v);
}

void mostrarMensagem(BuildContext context, String texto) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));

void mostrarErro(BuildContext context, Object erro) => mostrarMensagem(context, mensagemErro(erro));

/// Setas para subir/descer um item da lista
class BotoesOrdem extends StatelessWidget {
  final VoidCallback? aoSubir;
  final VoidCallback? aoDescer;
  const BotoesOrdem({super.key, this.aoSubir, this.aoDescer});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Subir',
          icon: const Icon(Icons.arrow_upward, size: 20),
          onPressed: aoSubir,
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Descer',
          icon: const Icon(Icons.arrow_downward, size: 20),
          onPressed: aoDescer,
        ),
      ]);
}

/// Campo de preço em reais ("12,50")
class CampoMoeda extends StatelessWidget {
  final TextEditingController controle;
  final String rotulo;
  final ValueChanged<String>? aoEnviar;
  final bool denso;
  const CampoMoeda({super.key, required this.controle, this.rotulo = 'Preço', this.aoEnviar, this.denso = false});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controle,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
        onSubmitted: aoEnviar,
        decoration: InputDecoration(
          labelText: rotulo,
          prefixText: r'R$ ',
          isDense: denso,
          border: const OutlineInputBorder(),
        ),
      );
}

/// Mensagem centralizada para lista vazia
class EstadoVazio extends StatelessWidget {
  final IconData icone;
  final String texto;
  final Widget? acao;
  const EstadoVazio({super.key, required this.icone, required this.texto, this.acao});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: Cores.primariaClara, shape: BoxShape.circle),
              child: Icon(icone, size: 36, color: Cores.primaria),
            ),
            const SizedBox(height: 16),
            Text(texto,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Cores.textoSuave, fontSize: 16, height: 1.4)),
            if (acao != null) ...[const SizedBox(height: 16), acao!],
          ]),
        ),
      );
}

/// Título de seção dentro de listas de configuração
class SecaoTitulo extends StatelessWidget {
  final String texto;
  const SecaoTitulo(this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(texto.toUpperCase(),
            style: const TextStyle(
              color: Cores.textoSuave,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            )),
      );
}

/// Máscara (11) 99999-9999 enquanto digita
class MascaraTelefone extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue antigo, TextEditingValue novo) {
    var d = apenasDigitos(novo.text);
    if (d.length > 11) d = d.substring(0, 11);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 0) b.write('(');
      if (i == 2) b.write(') ');
      if (i == (d.length == 11 ? 7 : 6)) b.write('-');
      b.write(d[i]);
    }
    final t = b.toString();
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// Telefone salvo (só dígitos, às vezes com 55) -> texto do campo com máscara
String telefoneParaCampo(String? tel) {
  if (tel == null || tel.isEmpty) return '';
  var d = apenasDigitos(tel);
  if (d.startsWith('55') && (d.length == 12 || d.length == 13)) d = d.substring(2);
  return MascaraTelefone().formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: d)).text;
}

/// Interruptor com o significado escrito embaixo (ex.: "À venda" / "Esgotado")
class InterruptorRotulado extends StatelessWidget {
  final bool valor;
  final String ligado;
  final String desligado;
  final ValueChanged<bool> aoMudar;
  const InterruptorRotulado({
    super.key,
    required this.valor,
    required this.ligado,
    required this.desligado,
    required this.aoMudar,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: valor,
        label: valor ? ligado : desligado,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 30,
            child: FittedBox(
              child: Switch(value: valor, onChanged: aoMudar, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ),
          Text(valor ? ligado : desligado,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: valor ? Cores.sucesso : Cores.textoSuave,
              )),
        ]),
      );
}

/// Miniatura de produto: foto ou a inicial do nome
class Miniatura extends StatelessWidget {
  final String? url;
  final String nome;
  final double tamanho;
  const Miniatura({super.key, this.url, required this.nome, this.tamanho = 56});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: tamanho,
          height: tamanho,
          child: url == null
              ? ColoredBox(
                  color: Cores.primariaClara,
                  child: Center(
                    child: Text(nome.isEmpty ? '?' : nome.characters.first.toUpperCase(),
                        style: TextStyle(fontSize: tamanho * 0.4, fontWeight: FontWeight.w800, color: Cores.primaria)),
                  ),
                )
              : Image.network(url!, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Cores.fundo, child: Icon(Icons.broken_image))),
        ),
      );
}

/// Linha de ajuda discreta no topo das listas
class Dica extends StatelessWidget {
  final String texto;
  const Dica(this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lightbulb_outline, size: 20, color: Cores.textoSuave),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(color: Cores.textoSuave, fontSize: 14))),
        ]),
      );
}
