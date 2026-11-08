import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../servicos/whatsapp_servico.dart';
import '../../util/formatar.dart';
import '../../widgets/comum.dart';

/// Conectar o WhatsApp da loja (código de pareamento ou QR Code) e ligar/desligar a IA
class TelaWhatsapp extends StatefulWidget {
  const TelaWhatsapp({super.key});

  @override
  State<TelaWhatsapp> createState() => _TelaWhatsappState();
}

class _TelaWhatsappState extends State<TelaWhatsapp> {
  final _servico = WhatsappServico.instancia;
  final _telefone = TextEditingController();
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _preferencias;
  bool _porQrCode = false;
  bool _ocupado = false;
  String? _erro;
  Timer? _acompanhar;

  @override
  void initState() {
    super.initState();
    _executar('status');
  }

  Future<void> _executar(String acao) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      final s = await _servico.conexao(
        acao,
        telefone: acao == 'conectar' && !_porQrCode ? apenasDigitos(_telefone.text) : null,
      );
      final p = await _servico.preferencias();
      if (!mounted) return;
      setState(() {
        _status = s;
        _preferencias = p;
      });
      _acompanharConexao();
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível falar com o WhatsApp. ${mensagemErro(e)}');
    }
    if (mounted) setState(() => _ocupado = false);
  }

  /// Enquanto aguarda o pareamento, consulta o status a cada 4 s
  void _acompanharConexao() {
    _acompanhar?.cancel();
    if (_status?['status_conexao'] != 'connecting') return;
    _acompanhar = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final s = await _servico.conexao('status');
        if (!mounted) return;
        setState(() {
          // mantém o código/QR na tela enquanto conecta
          _status = {..._status!, ...s, if (s['qrcode'] == null) 'qrcode': _status!['qrcode']};
        });
        if (s['status_conexao'] != 'connecting') {
          _acompanhar?.cancel();
          if (s['status_conexao'] == 'connected') mostrarMensagem(context, 'WhatsApp conectado!');
          _preferencias = await _servico.preferencias();
          if (mounted) setState(() {});
        }
      } catch (_) {}
    });
  }

  Future<void> _desconectar() async {
    final ok = await confirmar(context,
        titulo: 'Desconectar o WhatsApp?',
        texto: 'A IA para de acompanhar as conversas até você conectar de novo.',
        botao: 'Desconectar',
        perigo: true);
    if (ok) await _executar('desconectar');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status?['status_conexao'] as String?;
    final conectado = status == 'connected';
    final aguardando = status == 'connecting';
    final codigo = _status?['codigo_pareamento'] as String?;
    final qr = _status?['qrcode'] as String?;
    final cores = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp com IA')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          elevation: 0,
          color: conectado ? Colors.green.shade50 : cores.surfaceContainer,
          child: ListTile(
            leading: Icon(conectado ? Icons.check_circle : Icons.link_off,
                color: conectado ? Colors.green.shade700 : cores.outline, size: 32),
            title: Text(switch (status) {
              'connected' => 'Conectado',
              'connecting' => 'Aguardando você parear...',
              null => 'Verificando...',
              _ => 'Desconectado',
            }),
            subtitle: conectado && _status?['numero_conectado'] != null
                ? Text(formatarTelefone('${_status!['numero_conectado']}'))
                : const Text('A IA lê as conversas e monta os pedidos para você confirmar.'),
            trailing: IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _ocupado ? null : () => _executar('status'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!conectado) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Código pelo número'), icon: Icon(Icons.pin)),
              ButtonSegment(value: true, label: Text('QR Code'), icon: Icon(Icons.qr_code)),
            ],
            selected: {_porQrCode},
            onSelectionChanged: (s) => setState(() => _porQrCode = s.first),
          ),
          const SizedBox(height: 12),
          Text(
            _porQrCode
                ? 'Use se o WhatsApp da loja estiver em OUTRO celular: ele vai ler o QR Code desta tela.'
                : 'Use se o WhatsApp da loja está neste celular ou em outro: você digita um código no WhatsApp.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          if (!_porQrCode)
            TextField(
              controller: _telefone,
              keyboardType: TextInputType.phone,
              inputFormatters: [MascaraTelefone()],
              decoration: const InputDecoration(labelText: 'Número do WhatsApp da loja', border: OutlineInputBorder()),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _ocupado
                ? null
                : () {
                    if (!_porQrCode && apenasDigitos(_telefone.text).length < 10) {
                      return mostrarMensagem(context, 'Digite o número com DDD.');
                    }
                    _executar('conectar');
                  },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(_ocupado ? 'Aguarde...' : (_porQrCode ? 'Gerar QR Code' : 'Gerar código')),
          ),
          if (aguardando && !_porQrCode && codigo != null) ...[
            const SizedBox(height: 20),
            SelectableText(codigo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 8),
            const Text(
              'No WhatsApp da loja: ⋮ → Aparelhos conectados → Conectar um aparelho → '
              'Conectar com número de telefone, e digite este código.',
              textAlign: TextAlign.center,
            ),
          ],
          if (aguardando && _porQrCode && qr != null && qr.contains(',')) ...[
            const SizedBox(height: 20),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: Image.memory(base64Decode(qr.split(',').last), width: 260, height: 260, gaplessPlayback: true),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No outro celular, abra o WhatsApp da loja: ⋮ → Aparelhos conectados → Conectar um aparelho, e aponte para o QR Code.',
              textAlign: TextAlign.center,
            ),
          ],
        ] else
          OutlinedButton.icon(
            onPressed: _ocupado ? null : _desconectar,
            icon: const Icon(Icons.link_off),
            label: const Text('Desconectar'),
          ),
        if (_preferencias != null) ...[
          const SecaoTitulo('Preferências'),
          SwitchListTile(
            title: const Text('IA montando pedidos'),
            subtitle: const Text('Desligue para usar o WhatsApp sem a IA'),
            value: _preferencias!['ia_ativa'] as bool,
            onChanged: (v) async {
              setState(() => _preferencias!['ia_ativa'] = v);
              await _servico.salvarPreferencia('ia_ativa', v);
            },
          ),
          SwitchListTile(
            title: const Text('Entender áudios'),
            subtitle: const Text('A IA também ouve os áudios do cliente'),
            value: _preferencias!['transcrever_audio'] as bool,
            onChanged: (v) async {
              setState(() => _preferencias!['transcrever_audio'] = v);
              await _servico.salvarPreferencia('transcrever_audio', v);
            },
          ),
        ],
        if (_erro != null) ...[
          const SizedBox(height: 12),
          Text(_erro!, style: TextStyle(color: cores.error)),
        ],
      ]),
    );
  }

  @override
  void dispose() {
    _acompanhar?.cancel();
    _telefone.dispose();
    super.dispose();
  }
}
